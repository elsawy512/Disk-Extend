# Disk-Extend
Disk Extend automations process 
“Disk is 95% full. Urgent.”

You increase the disk in the cloud.

Linux sees the new size.

You run df -h.

Nothing changed.

Because storage isn’t one layer.

It’s:

Disk → Partition → PV → VG → LV → Filesystem

Miss one step and the expansion does nothing.

Under pressure, the usual fix is manual:

growpart
pvresize
lvextend
resize filesystem

It works.
But it’s repetitive.
And repetition under pressure is where mistakes happen.

Wrong disk.
Wrong LV.
No validation.

So I automated the entire flow.

One script.

It detects the stack.
Expands the partition if needed.
Resizes the PV.
Shows available free space.
Prompts for allocation percentage.
Extends the volume.
Grows the filesystem online.

No downtime.
No guessing.
No skipped layers.

Automation isn’t only about complex platforms.

Sometimes it’s about removing risk from the tasks we do every single week.
