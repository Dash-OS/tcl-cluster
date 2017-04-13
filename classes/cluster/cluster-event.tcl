::oo::define ::cluster::cluster method event {ns event args} {
  #puts " \n EVENT |  $NS  |  $event  |  $args \n"
  switch -nocase -glob -- $ns {
    cha* - channel { my ChannelEvent $event {*}$args }
    ser* - service { my ServiceEvent $event {*}$args }
  }
}

::oo::define ::cluster::cluster method ChannelEvent {event protocol {chanID {}} args} {
  lassign $args service
  set proto [my protocol $protocol]
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
      }
      if { $service ne {} } { 
        catch { $service event channel close $proto $chanID } 
      }
      dict unset CHANNELS $chanID
    }
    r* - receive {
      if { $service ne {} } { dict set CHANNELS $chanID service $service }
    }
    s* - server {
      # Server Channel refreshed - we need to send an updated protoprops
      if { "protoprops" ni $UPDATED_PROPS } {
        lappend UPDATED_PROPS protoprops
        my heartbeat_after 0
      }
    }
  }
  return
}

::oo::define ::cluster::cluster method ServiceEvent {event service args} {
  switch -glob -- $event {
    l* - lost {
      # Service lost event has occured
      my ServiceLostHook $service
      # Inform any protocols which have an event method that a service has been
      # lost.
      foreach protocol [$service protocols] {
        if { [dict exists $PROTOCOLS $protocol] } {
          # We dont care if it causes an error, we move on.
          catch { [dict get $PROTOCOLS $protocol] event service_lost $service }
        }
      }
    }
  }
}

::oo::define ::cluster::cluster method ServiceLostHook { service } {
  set cluster [self]
  try {my run_hook service lost} on error {r} { return }
}