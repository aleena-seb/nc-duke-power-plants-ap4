#!/usr/bin/env python3
"""Step 5: AP4 NC county damage tables and research-partner handoff.

Run at the repository root:
    python3 05_prepare_nc_county_results.py

Input: data/intermediate/ap4_nc/ap4_nc_scenario_results_2020usd.csv
Outputs: data/processed/ap4_nc/*.csv and step5_metadata.json

The 2026 USD adjustment is PROVISIONAL: January-October 2026 CPI-U average
divided by the 2020 annual CPI-U average, not a finalized 2026 annual index.
Source: https://www.bls.gov/regions/mid-atlantic/data/consumerpriceindexhistorical_us_table.htm
Figures are BLS nonseasonally adjusted CPI-U, US city average, all items.

IMPORTANT: Standalone site scenarios are counterfactuals, NOT additive
attributions. Only the All_11_Units scenario is used for NC damage rankings.
"""

from __future__ import annotations

import csv
import json
import math
import sys
from collections import defaultdict
from datetime import date
from pathlib import Path


CPI_2020_ANNUAL = 258.811
CPI_2026_JAN_OCT = [
    325.252, 326.785, 330.213, 333.020, 335.123,
    333.952, 333.918, 334.980, 336.940, 337.511,
]
CPI_2026_YTD = sum(CPI_2026_JAN_OCT) / len(CPI_2026_JAN_OCT)
USD_FACTOR = CPI_2026_YTD / CPI_2020_ANNUAL
CPI_SOURCE = (
    "https://www.bls.gov/regions/mid-atlantic/data/"
    "consumerpriceindexhistorical_us_table.htm"
)
SCENARIOS = [
    "All_11_Units", "Person", "Davie", "Marshall", "Buck",
    "Smith", "Belews Creek", "All_NOx_Only", "All_SO2_Only",
]
SITES = SCENARIOS[1:7]
FLOAT_FIELDS = [
    "baseline_pm25_ug_m3", "delta_pm25_ug_m3", "adult_expected_deaths",
    "infant_expected_deaths", "total_expected_deaths", "mortality_damage_2020_usd",
]
REQUIRED = {"scenario", "receptor_fips", "davie_source_approximation", *FLOAT_FIELDS}


def write_csv(path: Path, rows: list[dict], fields: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def load_and_check(path: Path) -> dict[str, dict[str, dict]]:
    grouped: dict[str, dict[str, dict]] = defaultdict(dict)
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"MATLAB export missing columns: {sorted(missing)}")
        for line_no, row in enumerate(reader, start=2):
            scenario = row["scenario"].strip()
            fips = row["receptor_fips"].strip().split(".")[0].zfill(5)
            if scenario not in SCENARIOS:
                raise ValueError(f"Unexpected scenario {scenario!r} on line {line_no}")
            if len(fips) != 5 or not fips.isdigit() or not fips.startswith("37"):
                raise ValueError(f"Invalid NC county FIPS {fips!r} on line {line_no}")
            if fips in grouped[scenario]:
                raise ValueError(f"Duplicate county {fips} for {scenario}")
            for field in FLOAT_FIELDS:
                try:
                    value = float(row[field])
                except (ValueError, TypeError) as exc:
                    raise ValueError(f"Invalid {field} on line {line_no}") from exc
                if not math.isfinite(value):
                    raise ValueError(f"Nonfinite {field} on line {line_no}")
                row[field] = value
            if row["delta_pm25_ug_m3"] < -1e-8:
                raise ValueError(f"Negative delta PM2.5 on line {line_no}")
            if row["mortality_damage_2020_usd"] < -0.01:
                raise ValueError(f"Negative damages on line {line_no}")
            if not math.isclose(
                row["adult_expected_deaths"] + row["infant_expected_deaths"],
                row["total_expected_deaths"], rel_tol=1e-6, abs_tol=1e-8,
            ):
                raise ValueError(f"Adult/infant mortality sum mismatch on line {line_no}")
            row["receptor_fips"] = fips
            grouped[scenario][fips] = row
    if set(grouped) != set(SCENARIOS):
        raise ValueError(f"Expected nine scenarios; found {sorted(grouped)}")
    reference = set(grouped["All_11_Units"])
    if len(reference) != 100 or any(set(rows) != reference for rows in grouped.values()):
        raise ValueError("Every scenario must contain exactly the same 100 NC counties")
    return grouped


def main() -> int:
    root = Path(__file__).resolve().parent
    source = root / "data/intermediate/ap4_nc/ap4_nc_scenario_results_2020usd.csv"
    if not source.is_file():
        print(f"ERROR: Missing MATLAB output:\n  {source}", file=sys.stderr)
        print("Copy this script into the repository root and run MATLAB Step 4 first.", file=sys.stderr)
        return 1
    grouped = load_and_check(source)
    destination = root / "data/processed/ap4_nc"
    destination.mkdir(parents=True, exist_ok=True)

    # Long-format panel for scenario-specific research and validation.
    long_rows = []
    for scenario in SCENARIOS:
        for fips in sorted(grouped[scenario]):
            row = grouped[scenario][fips]
            long_rows.append({
                **row,
                "mortality_damage_2026_usd_provisional":
                    row["mortality_damage_2020_usd"] * USD_FACTOR,
                "source_assumption": (
                    "Davie county-level non-EGU point-source proxy; "
                    "five legacy EGU row approximations"
                ),
                "model_baseline_year": 2017,
                "emissions_benchmark_year": 2024,
                "valuation_2026_status": "PROVISIONAL_JAN_OCT_CPI_U",
            })
    write_csv(destination / "ap4_scenarios_long_2026usd_provisional.csv", long_rows,
              list(long_rows[0]))

    # PRIMARY county ranking: combined 11-unit counterfactual only.
    primary = grouped["All_11_Units"]
    ranked = sorted(primary.values(), key=lambda r: -r["mortality_damage_2020_usd"])
    county_rows = []
    for rank, row in enumerate(ranked, 1):
        county_rows.append({
            "damage_rank_nc": rank,
            "receptor_fips": row["receptor_fips"],
            "delta_pm25_ug_m3": row["delta_pm25_ug_m3"],
            "baseline_pm25_ug_m3": row["baseline_pm25_ug_m3"],
            "adult_expected_deaths": row["adult_expected_deaths"],
            "infant_expected_deaths": row["infant_expected_deaths"],
            "total_expected_deaths": row["total_expected_deaths"],
            "mortality_damage_2020_usd": row["mortality_damage_2020_usd"],
            "mortality_damage_2026_usd_provisional":
                row["mortality_damage_2020_usd"] * USD_FACTOR,
            "nc_damage_share": row["mortality_damage_2020_usd"] /
                sum(r["mortality_damage_2020_usd"] for r in ranked),
        })
    write_csv(destination / "nc_receiving_counties_ranked.csv", county_rows,
              list(county_rows[0]))

    # Partner-ready WIDE data: FIPS join key, combined outcome, site scenarios.
    # Standalone damage columns are exploratory NONADDITIVE counterfactuals.
    partner_rows = []
    for county in county_rows:
        fips = county["receptor_fips"]
        wide = dict(county)
        for site in SITES:
            suffix = site.lower().replace(" ", "_")
            site_row = grouped[site][fips]
            wide[f"standalone_{suffix}_damage_2026_usd_provisional"] = (
                site_row["mortality_damage_2020_usd"] * USD_FACTOR
            )
            wide[f"standalone_{suffix}_delta_pm25_ug_m3"] = (
                site_row["delta_pm25_ug_m3"]
            )
        partner_rows.append(wide)
    write_csv(destination / "nc_demographic_regression_handoff.csv", partner_rows,
              list(partner_rows[0]))

    summary = []
    for scenario in SCENARIOS:
        rows = list(grouped[scenario].values())
        summary.append({
            "scenario": scenario,
            "nc_receptor_count": len(rows),
            "expected_annual_deaths_nc": sum(r["total_expected_deaths"] for r in rows),
            "damages_2020_usd_nc": sum(r["mortality_damage_2020_usd"] for r in rows),
            "damages_2026_usd_nc_provisional":
                sum(r["mortality_damage_2020_usd"] for r in rows) * USD_FACTOR,
        })
    write_csv(destination / "ap4_scenario_summary.csv", summary, list(summary[0]))

    combined = summary[0]
    # Check against the precise totals printed by the completed MATLAB run.
    if not math.isclose(combined["damages_2020_usd_nc"], 1992849.57,
                        rel_tol=0.001):
        raise ValueError("All-11 damages differ from prior MATLAB run; investigate")
    if not math.isclose(combined["expected_annual_deaths_nc"], 0.19982839,
                        rel_tol=0.001):
        raise ValueError("All-11 mortality differs from prior MATLAB run; investigate")

    metadata = {
        "generated_date": date.today().isoformat(),
        "input_file": str(source.relative_to(root)),
        "total_rows": len(long_rows),
        "nc_counties": 100,
        "scenario_count": len(SCENARIOS),
        "primary_outcome": "combined 11-unit mortality damages by NC receptor county",
        "cpi_2020_annual": CPI_2020_ANNUAL,
        "cpi_2026_jan_oct_mean": CPI_2026_YTD,
        "usd2020_to_usd2026_provisional_factor": USD_FACTOR,
        "cpi_source": CPI_SOURCE,
        "valuation_warning": (
            "2026 conversion uses Jan-Oct 2026 CPI-U average (latest available "
            "at preparation), not final calendar-year 2026 CPI. Base AP4 value "
            "is labeled 2020 USD in MATLAB output."
        ),
        "model_warning": (
            "AP4 chemistry is nonlinear; standalone sites and NOx/SO2 scenarios "
            "cannot be summed to reproduce combined damages. Historical 2017 "
            "AP4 exposures/population/mortality plus 2024 emissions benchmarks. "
            "Davie uses a county non-EGU point-source proxy; five other sites "
            "use historical EGU source-row approximations. No updated "
            "2024 population or facility-specific stack geometry is modeled."
        ),
        "geography_warning": "Receptors are limited to NC; damages outside NC excluded.",
        "regression_guidance": (
            "Join by receptor_fips as a 5-character string. Use combined damages "
            "as primary dependent variable. Do not add standalone site columns."
        ),
    }
    (destination / "step5_metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )

    print("Step 5 complete: 100 NC receptor counties, 9 scenarios.")
    print(f"2020 -> provisional 2026 CPI-U factor: {USD_FACTOR:.6f}")
    print(f"Combined expected deaths: {combined['expected_annual_deaths_nc']:.8f}")
    print(f"Combined damages 2020 USD: ${combined['damages_2020_usd_nc']:,.2f}")
    print("Combined damages provisional 2026 USD: "
          f"${combined['damages_2026_usd_nc_provisional']:,.2f}")
    print("Top five NC receiving counties (FIPS, 2026 provisional USD):")
    for row in county_rows[:5]:
        print(f"  {row['receptor_fips']}: "
              f"${row['mortality_damage_2026_usd_provisional']:,.2f}")
    print(f"Outputs: {destination}")
    print("CAUTION: provisional valuation and approximate source geometry.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, ZeroDivisionError) as err:
        print(f"STEP 5 FAILED: {err}", file=sys.stderr)
        raise SystemExit(1)
