#$service event channel close $protocol $chanID
::oo::define ::cluster::service method event { ns args } {
  switch -nocase -glob -- $ns {
    ch* - channel {
      lassign $args action proto chanID
      my ChannelEvent $action $proto $chanID
    }
  }
}

::oo::define ::cluster::service method ChannelEvent { action proto chanID } {
  #puts "Service Event Protocol is $proto $action"
  set protocol [$proto proto]
  switch -nocase -glob -- $action {
    cl* - close {
      if { [dict exists $SOCKETS $protocol] && [dict get $SOCKETS $protocol] eq $chanID } {
        dict unset SOCKETS $protocol
      }
    }
    op* - open {
      if { [dict exists $SOCKETS $protocol] && [dict get $SOCKETS $protocol] ne $chanID } {
        # A new channel is opening but we still have a reference to an older one?
        # We only allow one socket to each service per protocol - we call done on the previous
        $proto done [self] [dict get $SOCKETS $protocol] 0
      }
      dict set SOCKETS $protocol $chanID
    }
  }
}

