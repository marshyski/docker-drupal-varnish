FROM fedora:20
MAINTAINER Tim Marcinowski <marshyski@gmail.com>

USER root

RUN /bin/yum update -y
ADD ./install.sh /install.sh
ADD ./configs /configs
ADD ./drupal /drupal
RUN /bin/bash /install.sh
RUN /bin/cp -f /configs/httpd/httpd.conf /etc/httpd/conf/
RUN /bin/cp -f /configs/httpd/config.d/* /etc/httpd/conf.d/
RUN /bin/cp -f /configs/php/php.ini /etc/
RUN /bin/cp -f /configs/logrotate/httpd /etc/logrotate.d/
RUN /bin/cp -f /configs/ssmtp/* /etc/ssmtp/
RUN /bin/rm -rf /var/www/*
RUN /bin/cp -rf /drupal/* /var/www/

EXPOSE 80

CMD ["/usr/sbin/apachectl", "-D", "FOREGROUND"]
