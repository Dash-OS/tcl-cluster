# 0 - Disconnecting (Gracefully)
# 1 - Beacon / Heartbeat
# 2 - Discovery Request
# 3 - Services Ping Request
# 4 - Query
# 5 - Query Response
# 6 - Event
::oo::define ::cluster::cluster method get_type { type } {
  if { ! [string is entier -strict $type] } {
    switch -nocase -glob -- $type {
      discon* - close { set type 0 }
      bea* - heart*   { set type 1 }
      discov* - find  { set type 2 }
      ping            { set type 3 }
      q*              { set type 4 }
      res* - answ*    { set type 5 }
      event           { set type 6 }
      default { throw error "Unknown Type: $type" }
    } 
  }
  return $type
}

::oo::define ::cluster::cluster method get_channel { channel } {
  if { ! [string is entier -strict $channel] } {
    switch -nocase -glob -- $channel {
      broadcast - br* { set type 0 }
      system    - sy* { set type 1 }
      lan - lo* - la* { set type 2 }
      default { throw error "Unknown Channel: $channel" }
    }
  }
  return $channel
}

::oo::define ::cluster::cluster method payload { type channel payload {tags 0} {flags 1} } {
  set payload [dict merge [dict create \
    type      [my get_type $type] \
    channel   [my get_channel $channel] \
    hid       $SYSTEM_ID \
    sid       $SERVICE_ID \
    protocols [my protocols]
  ] $payload ]
  if { $flags } { dict set payload flags [my flags] }
  if { $tags  } { dict set payload tags $TAGS }
  return $payload
}

::oo::define ::cluster::cluster method discovery_payload { {props {}} {tags 0} {channel 0} {payload {}} } {
  if { $props ne {} } { dict set payload data [my props {*}$props] }
  return [my payload 2 $channel $payload $tags ]
}

::oo::define ::cluster::cluster method heartbeat_payload { {props {}} {tags 0} {channel 0} {payload {}} } {
  if { $props ne {} } { dict set payload data [my props {*}$props] }
  return [ my payload 1 $channel $payload $tags ]
}

::oo::define ::cluster::cluster method flush_payload { {props {}} {tags 0} {channel 0} {payload {}} } {
  if { $props ne {} } { dict set payload data [my props {*}$props] }
  return [ my payload 7 $channel $payload $tags ]
}

::oo::define ::cluster::cluster method query_payload { ruid query {filter {}} {channel 0} {tags 0} {flags 0} } {
  return [ my payload 4 $channel [dict create \
    ruid $ruid  \
    data $query \
    filter $filter \
    keepalive 1
  ] $tags $flags ]
}

::oo::define ::cluster::cluster method response_payload { response channel {tags 0} {flags 0} } {
  return [ my payload 5 $channel $response $tags $flags ]
}

# Services are a list of service_id's that are being requested.  They will be expected to
# respond and all services will decrease the TTL of the service in case it does not respond.
#
# When this command is sent, it is indicative to the cluster that at least one member has
# failed to communicate with a service.
#
# Because of this, the service is expected to make its response by broadcast as well.
::oo::define ::cluster::cluster method ping_payload { services {channel 0} } {
  return [ my payload 3 $channel [dict create \
    data $services 
  ]]
}

# Event Payload is sent when we simply want to send data to a member of the cluster. 
::oo::define ::cluster::cluster method event_payload { request channel {tags 0} {flags 0} } {
  return [ my payload 6 $channel $request $tags $flags ]
}