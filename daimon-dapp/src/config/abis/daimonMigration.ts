// GENERATO da scripts/generate-abis.mjs — non modificare a mano.
// Fonte: out/DaimonMigration.sol/DaimonMigration.json
export const daimonMigrationAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_oldDaimon",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_newDaimon",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_treasury",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_governance",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_migrationDurationSeconds",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "claim",
    "inputs": [
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "governance",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "migratedAmount",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "migrationDeadline",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "newDaimon",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract INewDaimon"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "oldDaimon",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IOldDaimon"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "sweepExecuted",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "sweepUnclaimed",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "totalMigrated",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "treasury",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "Claimed",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "Swept",
    "inputs": [
      {
        "name": "to",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AlreadySwept",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AmountMismatch",
    "inputs": []
  },
  {
    "type": "error",
    "name": "MigrationEnded",
    "inputs": []
  },
  {
    "type": "error",
    "name": "MigrationStillOpen",
    "inputs": []
  },
  {
    "type": "error",
    "name": "OnlyGovernance",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroAddress",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroAmount",
    "inputs": []
  }
] as const;
