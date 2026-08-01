from contextlib import redirect_stderr
import hashlib
import io
import unittest

import run_harness


class DescriptionTest(unittest.TestCase):
    def test_describes_hash_and_inputs(self):
        self.assertEqual(
            run_harness.describe(7, 16, 32, 64, b"blocks"),
            {
                "seed": 7,
                "width": 16,
                "height": 32,
                "depth": 64,
                "sha256": hashlib.sha256(b"blocks").hexdigest(),
            },
        )


class ArgumentValidationTest(unittest.TestCase):
    def test_accepts_power_of_two_dimensions(self):
        args = run_harness.parse_args(
            ["--seed", "7", "--width", "64", "--height", "128", "--depth", "32"]
        )
        self.assertEqual((args.width, args.height, args.depth), (64, 128, 32))

    def test_rejects_non_power_of_two_dimensions(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            run_harness.parse_args(["--seed", "7", "--width", "80"])


if __name__ == "__main__":
    unittest.main()
