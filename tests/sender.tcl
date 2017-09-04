if 0 {
  @ sender
    | Join the cluster and send data to the receiver
}

set script [file dirname [file normalize [info script]]]

::tcl::tm::path add [file join $script ../]

if {[file exists [file join $script socks]]} {
  file delete -force [file join $script socks]
}

file mkdir [file join $script socks]

package require cluster

try {
  set ::CLUSTER [cluster join \
    -address   230.230.220.220 \
    -port      22000 \
    -tags      [list receiver] \
    -channels  [list 5] \
    -protocols [list u t c] \
    -u [dict create \
      path [file join $script socks rx-unix]
    ]
  ]
} on error {result options} {
  puts "ERROR OCCURRED WHILE JOINING CLUSTER!"
  puts $result
  puts "-------------------------------------"
  puts $options
}

try {
  "Successfully Joined Cluster: $::CLUSTER"
}



vwait forever
