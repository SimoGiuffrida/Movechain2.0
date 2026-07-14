# MoveChain — Replication Package

This repository is the companion code for **"MoveChain: Real Implementation of Multi-Sensor Supply Chain Monitoring Using Move on Sui and IOTA."** It contains two parallel implementations of the same `SupplyChain` Move module — one deployed on **Sui**, one on **IOTA** — along with the scripts and raw results used to produce the cost and scalability figures reported in the paper.

## Repository Structure

```
.
├── SuiMovechain/           # Sui implementation
│   ├── Move.toml           # Package manifest (Sui Move dependency)
│   ├── sources/
│   │   ├── MoveChain.move        # SupplyChain module (movechain::SupplyChain)
│   │   └── benchmark_sui.ps1     # Scalability benchmark script (1–200 sensors)
│   ├── sui_benchmark_results.csv # Raw output of the scalability benchmark (→ paper Table 4)
│   └── README.md
│
└── IotaMovechain/          # IOTA implementation
    ├── Move.toml           # Package manifest (IOTA Move dependency)
    ├── Move.lock
    ├── sources/
    │   ├── movechain.move        # SupplyChain module (0x0::SupplyChain)
    │   └── benchmark_iota.ps1    # Scalability benchmark script (1–200 sensors)
    ├── test/
    │   └── testMovechain.move    # Move unit tests
    ├── iota_benchmark_results.csv # Raw output of the scalability benchmark (→ paper Table 4)
    ├── TransactionDigest.txt      # Sample CLI output of a package publish transaction
    └── README.md
```

Both `SupplyChain` modules expose the same six-function lifecycle API (`create_product`, `assign_distributor`, `assign_buyer`, `change_to_shared`, `update_sensor_data`, `confirm_delivery`), plus a sensor-registration function (`add_sensor` on Sui, `add_integer_sensor` on IOTA). The two implementations differ in how product lifecycle state and sensor storage are represented — see Section 4 ("MoveChain Smart Contract Architecture") and Table 1 of the paper for the full architectural comparison.

## Prerequisites

- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install) for `SuiMovechain/`
- [IOTA CLI](https://docs.iota.org/developer/getting-started/install-iota) for `IotaMovechain/`
- PowerShell (for the benchmark scripts, `*.ps1`)

## Building and Publishing

From inside each platform folder:

```bash
# Sui
cd SuiMovechain
sui move build
sui client publish --gas-budget 100000000

# IOTA
cd IotaMovechain
iota move build
iota client publish --gas-budget 100000000
```

Publishing prints a `PackageID`, which is required by the benchmark scripts below.

## Reproducing the Scalability Benchmark (Paper Table 4 / Fig. 5)

Each platform folder includes a PowerShell script that creates a product, attaches a configurable number of sensors (1, 5, 25, 50, 75, 100, 200), and measures `update_sensor_data()` latency over 10 repeated calls per load level.

1. Open `sources/benchmark_sui.ps1` (or `benchmark_iota.ps1`) and set `$PackageID` to the package ID obtained when publishing.
2. Run the script from PowerShell:
   ```powershell
   ./sources/benchmark_sui.ps1     # or benchmark_iota.ps1
   ```
3. Results are written to `sui_benchmark_results.csv` / `iota_benchmark_results.csv` (`NumSensors, AvgTime_ms, StdDev_ms`), matching the values reported in Table 4 of the paper.

## Tests

`IotaMovechain/test/testMovechain.move` contains Move unit tests for the `SupplyChain` module.

## Notes on Files in This Package

- `SuiMovechain/README.md` and `IotaMovechain/README.md` document each module's API in more detail.
- `TransactionDigest.txt` is a saved CLI transcript of a real `publish` call on IOTA testnet, kept as a deployment reference.
