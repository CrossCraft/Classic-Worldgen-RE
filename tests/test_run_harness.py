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

    def test_describes_present_block_ids_and_requested_groups(self):
        result = run_harness.describe_composition(
            bytes([0, 1, 1, 8, 9, 14, 15, 16, 17, 18, 255])
        )

        self.assertEqual(result["total"], 11)
        self.assertEqual(
            [(block["id"], block["name"], block["count"])
             for block in result["blocks"]],
            [
                (0, "air", 1),
                (1, "stone", 2),
                (8, "flowing_water", 1),
                (9, "still_water", 1),
                (14, "gold_ore", 1),
                (15, "iron_ore", 1),
                (16, "coal_ore", 1),
                (17, "log", 1),
                (18, "leaves", 1),
                (255, "unknown", 1),
            ],
        )
        self.assertEqual(result["groups"]["water"]["count"], 2)
        self.assertEqual(result["groups"]["ore"]["count"], 3)

    def test_plausibility_check_accepts_a_typical_small_composition(self):
        blocks = (
            bytes([1]) * 2000
            + bytes([9]) * 200
            + bytes([3]) * 512
            + bytes([2]) * 128
            + bytes([17]) * 10
            + bytes([18]) * 100
            + bytes([10]) * 256
            + bytes([16]) * 100
            + bytes([0]) * 790
        )

        result = run_harness.check_composition(16, 16, 16, blocks)

        self.assertTrue(result["ok"])

    def test_plausibility_check_rejects_an_empty_world(self):
        result = run_harness.check_composition(16, 16, 16, bytes(4096))

        self.assertFalse(result["ok"])

    def test_plausibility_check_allows_absent_ore_on_a_tiny_map(self):
        blocks = (
            bytes([1]) * 336
            + bytes([2]) * 40
            + bytes([3]) * 776
            + bytes([9]) * 483
            + bytes([10]) * 256
            + bytes([0]) * 2205
        )

        result = run_harness.check_composition(16, 16, 16, blocks)

        self.assertTrue(result["ok"])

    def test_surface_checks_use_width_times_depth(self):
        result = run_harness.check_composition(
            16, 64, 32, bytes([2]) * (16 * 32) + bytes(16 * 64 * 32 - 16 * 32)
        )
        grass = next(
            check for check in result["checks"] if check["group"] == "grass"
        )

        self.assertEqual(grass["normalized"], 1.0)


class ArgumentValidationTest(unittest.TestCase):
    def test_accepts_power_of_two_dimensions(self):
        args = run_harness.parse_args(
            ["--seed", "7", "--width", "64", "--height", "32", "--depth", "128"]
        )
        self.assertEqual((args.width, args.height, args.depth), (64, 32, 128))

    def test_default_dimensions_use_vertical_height_in_the_middle(self):
        args = run_harness.parse_args(["--seed", "7"])

        self.assertEqual((args.width, args.height, args.depth), (256, 64, 256))

    def test_rejects_non_power_of_two_dimensions(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            run_harness.parse_args(["--seed", "7", "--width", "80"])


if __name__ == "__main__":
    unittest.main()
