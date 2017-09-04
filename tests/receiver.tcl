
if 0 {
  @ receiver
    | Simply join the cluster and register hooks to print what
    | we recieve.
}
set script [file dirname [file normalize [info script]]]
::tcl::tm::path add [file join $script ../]


if {[file exists [file join $script socks]]} {
  file delete -force [file join $script socks]
}

file mkdir [file join $script socks]

puts "Requiring Cluster Package"

if { [info commands ::onError] eq {} } {
  # Our Error Handler is called throughout.  If not defined, we define it
  # here.
  # TODO: Provide official way to handle the logging / errors.
  proc ::onError { result options args } {
    puts "Error Occurred!"
    puts $result
    puts $options
  }
}

package require cluster

try {
  set ::CLUSTER [cluster join \
    -address   230.230.220.220 \
    -port      22000 \
    -tags      [list receiver] \
    -channels  [list 5] \
    -protocols [list u t c] \
    -remote 1 \
    -u [dict create \
      path [file join $script socks rx2-unix]
    ]
  ]
} on error {result options} {
  puts "ERROR OCCURRED WHILE JOINING CLUSTER!"
  puts $result
  puts "-------------------------------------"
  puts $options
  exit 1
}

$::CLUSTER hook service discovered {
  puts "
    ----- HOOK: EVALUATE DISCOVER -----
      Service: $service

      [$service info]
      [$service tags]
    ------------------------------------
  "
}

$::CLUSTER hook evaluate receive {
  puts "
    ----- HOOK: EVALUATE RECEIVE -----

     Protocol:   $protocol
     Descriptor: $descriptor
     Payload:
     $payload
    ----------------------------------
  "
}

vwait forever
