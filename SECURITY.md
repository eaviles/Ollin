# Security

If you find a vulnerability in Ollin, please report it privately through [GitHub's private vulnerability reporting](https://github.com/eaviles/Ollin/security/advisories/new) (the repository's Security tab, then "Report a vulnerability") rather than in a public issue.

Ollin is a nights-and-weekends project with no promised response time, but private reports get read first.

Two notes on scope:

- A sketch is a Swift program you compile and run yourself. That a sketch can execute code, read files, or open the network is the framework working as designed, not a vulnerability.
- The surfaces that listen or serve are in scope: the remote parameter surface, OSC, MIDI, serial, Bluetooth, the multi-machine room protocol, and every file and network loader.
