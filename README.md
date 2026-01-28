# CCDC-Resources
Shell scripts and other utilities for hardening CCDC systems.

Todo: Create Bash script that takes in a list of PCR accounts.
The script will identify all local accounts that do NOT match the PCR list, then prompt the user for confirmation.
When given, the script will then lock and strip permission groups from all non PCR accounts.
It will also identify all authorized_keys files, and remove them from the identified user accounts.

Potential additional features:
- Creation of the failsafe account
- Locking root
- Archive backup of important common directories like /etc/, /var/www/
