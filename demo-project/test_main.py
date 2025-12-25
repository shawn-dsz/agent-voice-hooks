#!/usr/bin/env python3
"""Tests for demo app"""

import unittest
from main import greet

class TestMain(unittest.TestCase):
    def test_greet(self):
        self.assertEqual(greet("World"), "Hello, World!")
        self.assertEqual(greet("Claude"), "Hello, Claude!")

if __name__ == "__main__":
    unittest.main()
