# Notes, Research, References

Notes and references on items that may need a deeper understanding on "why" we take a certain action.  If you find conflicting, or more up to date resources, let me know!

## fstrim - Disable inside LXC?  How to run?

Not needed to run inside LXC, Official instructions are to run on Host.  Several forum posts from Proxmox Staff instructing not to run inside of LXC, but on the host itself.

That makes sense to me, as LXC's don't use block devices.  Trim is usually handled by the block device owner, running it in the LXC would be redundant.

Proxmox documentation instructing to run fstrim:
https://pve.proxmox.com/pve-docs/pct.1.html

Proxmox staff forum post instructing to run on host:
https://forum.proxmox.com/threads/fstrim-doesnt-work-in-containers-any-os-workarounds.54421/

More recent post of proxmox staff saying not needed to run inside lxc:
https://forum.proxmox.com/threads/lxc-disk-trimming-discard.175374/