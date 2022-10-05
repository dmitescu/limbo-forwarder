# Synopsis
svc/forwarder is a simple Inferno program that creates and manages
network port forwards using/across net filesystems.

Usage:

```
mount 'tcp!inferno.mydomain.tld!6695' /net.alt
svc/forwarder -F 'tcp!irc.libera.org!6697' '/net.alt/tcp!*!6697'
```

For a full description of the arguments, check `forwarder(1)`.

# Why?

Why not?
