# -*- coding: utf-8 -*-
import os
import random


# 50% results ZeroDivisionError
def say_hello():
    name = os.getenv("NAME", "batch")

    if random.random() > 0.5:
        print("hello %s!" % name)
    else:
        print(1 / 0)


if __name__ == "__main__":
    say_hello()
