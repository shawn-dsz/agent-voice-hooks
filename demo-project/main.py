#!/usr/bin/env python3
"""A simple demo app for testing"""

def greet(name):
    return f"Hello, {name}!"

def main():
    names = ["World", "Claude", "Voice Mode"]
    for name in names:
        print(greet(name))

if __name__ == "__main__":
    main()
