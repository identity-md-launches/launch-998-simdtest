#!/usr/bin/env python3
"""Check this assignment's manifest values against its compiled token artifact.

This is a local consistency check, not the network's independent schema validator.
Run forge build first. Uses only the Python standard library.
"""

import json
from pathlib import Path
import re


def check(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / "launch.json").read_text())
    check(
        set(manifest) == {"kind", "token", "contracts", "pool", "economics", "notes"},
        "Unexpected manifest fields (chainId is not a valid root field).",
    )
    check(manifest["kind"] == "custom_token", "Wrong launch kind.")
    check(manifest["contracts"] == [], "This launch has no application contracts.")
    check(isinstance(manifest["notes"], str), "Notes must be a string.")
    token = manifest["token"]
    check(
        re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,31}", token["contract"]) is not None,
        "token.contract must be a plain Solidity name fitting bytes32.",
    )
    check(token == {
        "contract": "SIMDTESTToken", "name": "SIMDTEST", "symbol": "SIMDTEST",
        "decimals": 18, "constructorArgs": [], "totalSupply": str(10**27),
    }, "Token metadata does not match the assignment.")
    check(manifest["pool"] == {
        "pairedCurrency": "0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7",
        "fee": 3000, "tickSpacing": 60, "initialPrice": "125270724187523965593206900",
    }, "Pool parameters do not match the assignment.")
    check(manifest["economics"] == {
        "poolBps": 9000, "initialMarketCapWei": "2500000000000000000000",
        "remainderTo": "0x000000000000000000000000000000000000dead",
    }, "Economics do not match the assignment.")

    artifact = json.loads((root / "out/SIMDTESTToken.sol/SIMDTESTToken.json").read_text())
    abi = artifact["abi"]
    constructors = [entry for entry in abi if entry["type"] == "constructor"]
    check(len(constructors) == 1 and constructors[0]["inputs"] == [], "Unexpected constructor arguments.")
    check(not any(entry["type"] in {"fallback", "receive"} for entry in abi), "Unexpected fallback/receive.")
    functions = [entry for entry in abi if entry["type"] == "function"]
    mutating = {entry["name"] for entry in functions if entry["stateMutability"] not in {"view", "pure"}}
    check(mutating == {"transfer", "approve", "transferFrom"}, "Unexpected state-changing API.")
    metadata = artifact.get("metadata") or json.loads(artifact["rawMetadata"])
    check(metadata["compiler"]["version"].startswith("0.8.26+"), "Compiler is not 0.8.26.")
    settings = metadata["settings"]
    check(settings["evmVersion"] == "cancun", "EVM version is not Cancun.")
    check(settings["optimizer"] == {"enabled": True, "runs": 200}, "Unexpected optimizer settings.")
    check(settings["metadata"]["bytecodeHash"] == "none", "Metadata bytecode hash is enabled.")
    print("Manifest values, constructor, public write API, and compiler settings match the assignment.")


if __name__ == "__main__":
    main()
