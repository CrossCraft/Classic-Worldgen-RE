"""Persistent, SQLite-backed differential fuzzing for Classic worldgen."""

from .campaign import CASE_GENERATOR_VERSION, Case, fixed_cases, random_case

__all__ = [
    "CASE_GENERATOR_VERSION",
    "Case",
    "fixed_cases",
    "random_case",
]
