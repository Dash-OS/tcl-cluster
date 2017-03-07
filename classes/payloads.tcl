
# A helper to assist us with building a valid cluster payload.
::oo::define ::cluster::cluster method payload { type channel payload {tags 0} {flags 1} } {
  set payload [dict merge [dict create \
    type      [my type $type] \
    channel   [my channel $channel] \
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