# Prompt for the `rog` User Password

## Goal

Set an interactive password for the `rog` administrator account when the setup script creates that account, while preserving any existing password on repeat runs.

## Design

The user configuration flow will track whether `rog` existed before attempting creation. If the account is newly created, the script will:

1. Prompt silently for a password.
2. Prompt silently a second time for confirmation.
3. Reject empty passwords or mismatched confirmations with a clear error.
4. Set the password through `chpasswd`, providing the secret through standard input rather than command-line arguments or logs.

If `rog` already exists, the script will not prompt and will not modify its password. Dry runs will not prompt or invoke password-changing commands.

## Testing

The fake-root test suite will provide a `chpasswd` stub and simulated standard input. Tests will verify that:

- A new account receives the entered password.
- The password does not appear in recorded command output.
- A second setup run does not prompt or call `chpasswd` again.
- Empty and mismatched passwords fail before password configuration completes.
- Dry runs remain non-mutating and do not require password input.

## Security and compatibility

The password will never be accepted as a command-line option or environment variable. The prompt will suppress terminal echo where possible and restore terminal behavior through Bash's `read -s` handling. Existing account data remains untouched.
