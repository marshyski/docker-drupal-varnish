#!/usr/bin/python

from locust import HttpLocust, TaskSet, task

class MyTaskSet(TaskSet):
    @task(1)
    def index(self):
        self.client.get("/")

    @task(2)
    def mission(self):
        self.client.get("/mission")

    @task(3)
    def events(self):
        self.client.get("/events")

    @task(4)
    def media(self):
        self.client.get("/media")

    @task(5)
    def store(self):
        self.client.get("/store")

    @task(6)
    def support(self):
        self.client.get("/support")

    @task(7)
    def contact(self):
        self.client.get("/contact")

class MyLocust(HttpLocust):
    task_set = MyTaskSet
    min_wait = 5000
    max_wait = 15000
    host = "http://test.woundedwear.org"
