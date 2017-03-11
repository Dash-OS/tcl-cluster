::oo::define ::cluster::cluster method event {ns event proto args} {
  switch -nocase -glob -- $ns {
    cha* - channel { my ChannelEvent $event $proto {*}$args }
  }
}

::oo::define ::cluster::cluster method ChannelEvent {event proto {chanID {}} args} {
  switch -nocase -glob -- $event {
    o* - opens {
      lassign $args service
      dict set CHANNELS $chanID [dict create \
        proto    $proto \
        created  [clock seconds]
      ]
      if { $service ne {} } { 
        dict set CHANNELS $chanID service $service
        $service event channel open $proto $chanID
      }
    }
    c* - close {
      if { [dict exists $CHANNELS $chanID service] } {
        set service [dict get $CHANNELS $chanID service]
      } else { lassign $args service }
      if { $service ne {} } { catch { $service event channel close $proto $chanID } }
      dict unset CHANNELS $chanID
    }
    r* - receive {
      lassign $args service
      if { $service ne {} } { dict set CHANNELS $chanID service $service }
    }
  }
  return
}

::oo::define ::cluster::cluster method service_lost { service } {
  set cluster [self]
  try [my run_hook service lost] on error {r} { return }
}