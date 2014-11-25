/* Backend definitions.*/
backend default {
  /* Default backend on the same machine. WARNING: timeouts could be not big enought for certain POST request */
  .host = "0.0.0.0";
  .port = "8080";
  .connect_timeout = 60s;
  .first_byte_timeout = 60s;
  .between_bytes_timeout = 60s;
}

/* Access Control Lists */
acl purge_ban {
  /* Simple access control list for allowing item purge for the self machine */
  "127.0.0.1"/32; // We can use '"localhost";' instead
}
acl allowed_monitors {
  /* Simple access control list for allowing item purge for the self machine */
  "127.0.0.1"/32; // We can use'"localhost";' instead
}

/* VCL logigc overrides */
sub vcl_recv {
  /* 1st: Check for Varnish special requests */ 
  if (req.request == "PURGE") {
    if (!client.ip ~ purge_ban) {
      error 405 "Not allowed.";
    }
    return (lookup);
  }
  if (req.request == "BAN") {
    if (!client.ip ~ purge_ban) {
      error 405 "Not allowed.";
    }
    ban("req.http.host == " + req.http.host +
      "&& req.url == " + req.url);    
    error 200 "Ban added";
  }
  if (req.http.host == "monitor.server.health" && 
      client.ip ~ allowed_monitors && 
      (req.request == "OPTIONS" || req.request == "GET")) {
    error 200 "Ok";
  }

  /* 4th: Set custom headers for backend like X-Forwarded-For (copied from built-in logic) */
  if (req.restarts == 0) {
    /* See also vcl_pipe section */
    if (req.http.x-forwarded-for) {
      set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    } else {
      set req.http.X-Forwarded-For = client.ip;
    }
  }

  /* 6th: Decide if we should deal with a request (mostly copied from built-in logic) */
  if (req.request != "GET" &&
      req.request != "HEAD" &&
      req.request != "POST" &&
      req.request != "TRACE" &&
      req.request != "OPTIONS") {
    /* Non-RFC2616 or CONNECT which is weird. */
    return (pipe);
  }
  if (req.request != "GET" && req.request != "HEAD") {
    /* We only deal with GET and HEAD by default */
    return (pass);
  }
  if (req.http.Authorization) {
    /* Not cacheable by default */
    return (pass);
  }

  /* 8th: Custom exceptions */
  if (req.url ~ "^/status\.php$" ||
      req.url ~ "^/update\.php$" ||
      req.url ~ "^/ooyala/ping$" ||
      req.url ~ "^/admin/build/features" ||
      req.url ~ "^/info/.*$" ||
      req.url ~ "^/flag/.*$" ||
      req.url ~ "^.*/ajax/.*$" ||
      req.url ~ "^.*/ahah/.*$") {
    /* Do not cache these paths */
    return (pass);
  }
  if (req.url ~ "^/admin/content/backup_migrate/export") {
    return (pipe);
  }
  if (req.url ~ "^/system/files") {
    return (pipe);
  }

  /* 9th: Enable grace mode */
  if (! req.backend.healthy) {
    /* Use a longer grace period if all backends are down */
    set req.grace = 1h;
    /* Use anonymous, cached pages if all backends are down. */
    unset req.http.Cookie;
  } else {
    /* Allow the backend to serve up stale content if it is responding slowly. */
    set req.grace = 30s;
  }

  /* 10th: Deal with compression and the Accept-Encoding header */
  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|mp4|flv|zip|rar)$") {
      /* Already compressed formats, no sense trying to compress again */
      remove req.http.Accept-Encoding;
    }
  }

  /* 13th: Session cookie & special cookies bypass caching stage */
  if (req.http.Cookie ~ "SESS" ||
      req.http.Cookie ~ "SSESS" ||
      req.http.Cookie ~ "NO_CACHE") {
    return (pass);
  }

  /* 15th: Bypass built-in logic */
  return (lookup);
}

sub vcl_pipe {
  /* Prevent connection re-using for piped requests */
  set bereq.http.connection = "close";

  /* Bypass built-in logic */
  return (pipe);
}

sub vcl_hash {
  hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
  /* ELB sets called X-Forwarded-Proto need this for SS: termination */
  if (req.http.X-Forwarded-Proto) {
    hash_data(req.http.X-Forwarded-Proto);
  }
  return (hash);
}

sub vcl_hit {
  /* Check for Varnish special requests */ 
  if (req.request == "PURGE") {
    purge;
    error 200 "Purged.";
  }
}

sub vcl_miss {
  /* Check for Varnish special requests */ 
  if (req.request == "PURGE") {
    purge;
    error 200 "Purged.";
  }
}

sub vcl_fetch {
  /* Caching exceptions */
  if (beresp.status == 307 &&
      beresp.http.Location == req.url &&
      beresp.ttl > 5s) {
    set beresp.ttl = 5s;
    set beresp.http.cache-control = "max-age=5";
  }

  /* Enable grace mode. Related with our 9th stage on vcl_recv */
  set beresp.grace = 1h;

  /* Enable saint mode. Related with our 9th stage on vcl_recv */
  if (beresp.status == 500) {
    set beresp.saintmode = 20s;
    return(restart);
  }

  /* Strip cookies from the following static file types for all users. Related with our 12th stage on vcl_recv */
  if (req.url ~ "(?i)\.(png|gif|jpeg|jpg|ico|swf|css|js|html|htm|gz|tgz|bz2|tbz|mp3|ogg|zip|rar|otf|ttf|eot|woff|svg|pdf)(\?[a-z0-9]+)?$") {
    unset beresp.http.set-cookie;
  }

  /* Gzip response */
  if (beresp.http.content-type ~ "text/plain"
    || beresp.http.content-type ~ "text/xml"
    || beresp.http.content-type ~ "text/css"
    || beresp.http.content-type ~ "text/html"
    || beresp.http.content-type ~ "application/(x-)?javascript"
    || beresp.http.content-type ~ "application/(x-)?font-ttf"
    || beresp.http.content-type ~ "application/(x-)?font-opentype"
    || beresp.http.content-type ~ "application/font-woff"
    || beresp.http.content-type ~ "application/vnd\.ms-fontobject"
    || beresp.http.content-type ~ "image/svg\+xml"
    ) {
       set beresp.do_gzip = true;
  }

  /* Debugging headers */
  if (beresp.ttl <= 0s) {
    /* Varnish determined the object was not cacheable */
    set beresp.http.X-Cacheable = "NO:Not Cacheable";
  } elsif (req.http.Cookie ~ "(SESS|SSESS|NO_CACHE)") {
    /* We don't wish to cache content for logged in users or with certain cookies. Related with our 9th stage on vcl_recv */
    set beresp.http.X-Cacheable = "NO:Cookies";
  } elsif (beresp.http.Cache-Control ~ "private") {
    /* We are respecting the Cache-Control=private header from the backend */
    set beresp.http.X-Cacheable = "NO:Cache-Control=private";
  } else {
    /* Varnish determined the object was cacheable */
    set beresp.http.X-Cacheable = "YES";
  }

  /* Further header manipulation */
    unset beresp.http.X-Powered-By;
    unset beresp.http.Server;
    unset beresp.http.X-Drupal-Cache;
    unset beresp.http.X-Varnish;
    unset beresp.http.Via;
    unset beresp.http.Link;
}

sub vcl_deliver {
  /* Debugging headers */
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";
    set resp.http.X-Cache-Hits = obj.hits;
  } else {
    set resp.http.X-Cache = "MISS";
    /* Show the results of cookie sanitization */
    set resp.http.X-Cookie = req.http.Cookie;
  }
  if ( req.restarts > 0) {
    set resp.http.X-Restarts = req.restarts;
  }
  set resp.http.X-Varnish-Server = server.hostname;
}

sub vcl_error {
  /* Avoid DOS vulnerability CVE-2013-4484 */
  if (obj.status == 400 || obj.status == 413) {
    return(deliver);
  }

  if (obj.status == 503 && req.restarts < 4) {
    set obj.http.X-Restarts = req.restarts;
    return(restart);
  }

  /* Set common headers for synthetic responses */
  set obj.http.Content-Type = "text/html; charset=utf-8";

  /* We're using error 200 for monitoring puposes */
  if (obj.status == 200) {
    synthetic {"
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
      "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
      <html>
        <head>
          <title>"} + obj.status + " " + obj.response + {"</title>
      </head>
      <body><h1>"} + obj.status + ": " + obj.response + {"</h1></body>
    "};
    return(deliver);
  }

  /* Error page & refresh / redirections */
  set obj.http.Retry-After = "5";
  synthetic {"
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
  <head>
    <title>"} + obj.status + " " + obj.response + {"</title>
  </head>
  <body>
    <h1>Error "} + obj.status + " " + obj.response + {"</h1>
    <p>"} + obj.response + {"</p>
    <h3>Guru Meditation:</h3>
    <p>XID: "} + req.xid + {"</p>
    <hr>
    <hr>
    <p>Varnish cache server</p>
  </body>
</html>
"};

  /* Bypass built-in logic */
  return (deliver);
}


