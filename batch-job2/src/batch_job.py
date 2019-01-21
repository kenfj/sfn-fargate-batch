# -*- coding: utf-8 -*-
import random


# 20% results IndexError
def say_hello():
    if random.random() > 0.2:
        print("hello batch 2!")
    else:
        tmp = []
        print(tmp[1])


if __name__ == "__main__":
    say_hello()
