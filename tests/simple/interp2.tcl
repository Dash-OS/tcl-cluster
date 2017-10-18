package require cluster

proc await {{time 0}} {
  after $time { set ::await 1 }
  vwait ::await
}

variable script_dir [file normalize \
  [file dirname [info script]]
]

if {$script_dir eq {}} {
  set script_dir [file normalize $::env(HOME)]
}

puts "Script Directory: $script_dir"

set ::CLUSTER [cluster join \
  -tags [list TWO]
]

$CLUSTER hook service discovered {
  puts "
    New Service Discovered!

    Tags: [$service tags]
  "
}

puts "
  Cluster Joined!

  Hardware ID: [$CLUSTER hid]
  Service ID:  [$CLUSTER sid]

  Known Services:
  [$CLUSTER services]
"

vwait __forever__
