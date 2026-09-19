"""Seed the database.

Usage::

    python -m app.seeds            # reference data only (safe in production)
    python -m app.seeds --demo     # reference data + demo account & history
"""

from __future__ import annotations

import argparse
import asyncio

from app.core.logging import configure_logging, get_logger
from app.db.session import SessionFactory
from app.seeds.seeder import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    DEMO_EMAIL,
    DEMO_PASSWORD,
    seed_demo_data,
    seed_reference_data,
)

logger = get_logger(__name__)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Seed the FitTrack database")
    parser.add_argument(
        "--demo", action="store_true", help="also create the demo account and history"
    )
    parser.add_argument(
        "--weeks", type=int, default=12, help="weeks of demo training history"
    )
    args = parser.parse_args()

    configure_logging()
    async with SessionFactory() as session:
        if args.demo:
            await seed_demo_data(session, weeks=args.weeks)
            print("\nDemo accounts ready:")
            print(f"  user   {DEMO_EMAIL} / {DEMO_PASSWORD}")
            print(f"  admin  {ADMIN_EMAIL} / {ADMIN_PASSWORD}\n")
        else:
            await seed_reference_data(session)
            print("Reference data seeded (exercises, foods, templates).")


if __name__ == "__main__":
    asyncio.run(main())
