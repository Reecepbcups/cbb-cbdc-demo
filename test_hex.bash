#!/bin/bash

# Function to validate Ethereum address
# validate_address() {
#     local address="$1"
#     if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
#         echo "Invalid Ethereum address format. Must be 0x followed by 40 hex characters."
#         exit 1
#     }
# }

# Function to convert amount to wei and hex
amount_to_hex() {
    local amount="$1"
    # Convert to wei (multiply by 10^18)
    local wei=$(printf "%.0f" "$(echo "$amount * 10^18" | bc)")
    # Convert to hex and pad to 64 characters
    printf "%064x" "$wei"
}

# Generate ERC20 transfer payload
generate_transfer_payload() {
    local address="$1"
    local amount="$2"

    # Remove 0x prefix from address if present
    address="${address#0x}"

    # Transfer function signature: transfer(address,uint256)
    # https://ethereum.stackexchange.com/questions/3584/what-is-the-use-of-the-payload-field-in-the-ethereum-transaction-reciept
    local function_selector="a9059cbb" # remove 0x prefix if any

    # Pad address to 32 bytes (64 characters)
    local padded_address="000000000000000000000000$address"

    # Convert and pad amount
    local padded_amount=$(amount_to_hex "$amount")

    # Concatenate all parts
    echo "${function_selector}${padded_address}${padded_amount}"
}

# Check if all arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <recipient_address> <amount>"
    echo "Example: $0 0x742d35Cc6634C0532925a3b844Bc454e4438f44e 100"
    exit 1
fi

# Validate address
# validate_address "$1"

# Generate and output payload
generate_transfer_payload "$1" "$2"
