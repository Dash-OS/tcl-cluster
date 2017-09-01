namespace eval ::cluster {}
namespace eval ::cluster::packet {
  variable total_encoded 0
}

set ::cluster::packet::encoder [::bpacket::writer new]

if 0 {
  @ bpacket template
    > Summary
    | This builds our binary format template.  It is utilized by both the
    | encoding and decoding end to understand how to build and parse our
    | binary formatting  automatically.
    TODO:
      * asterix items are marked as required, although this is not
      * currently enforced.
}
$::cluster::packet::encoder template {
  * flags  type channel   | 1
  * string hid            | 2
  * string sid            | 3
    flags  known f2 f3 f4 | 4
    vint   timestamp      | 5
  * list   protocols      | 6
    string ruid           | 7
    string op             | 8
    string data           | 9
    aes    raw            | 10
    list   tags           | 11
    bool   keepalive      | 12
    list   filter         | 13
    string error          | 14
}

proc ::cluster::packet::encode { payload } {
  $::cluster::packet::encoder reset

  if { [dict exists $payload filter] } {
    # Filters are always first to be encoded.  This allows us to quickly cancel
    # parsing if a service does not match our filter.
    dict set prefix 13 [dict get $payload filter]
  } else { set prefix [dict create] }

  set packet_dict [dict merge $prefix [dict create \
    1 [list [dict get $payload type] [dict get $payload channel]] \
    2 [dict get $payload hid] \
    3 [dict get $payload sid] \
    5 [clock seconds] \
    6 [dict get $payload protocols]
  ]]
  if { [dict exists $payload error] } {
    dict set packet_dict 14 [dict get $payload error]
  }
  if { [dict exists $payload flags] } { dict set packet_dict 4 [dict get $payload flags] }
  if { [dict exists $payload ruid] && [dict get $payload ruid] ne {} } {
    dict set packet_dict 7 [dict get $payload ruid]
  }

  if { [dict exists $payload op] && [dict get $payload op] ne {} } {
    dict set packet_dict 8 [dict get $payload op]
  }
  if { [dict exists $payload data] && [dict get $payload data] ne {} } {
    dict set packet_dict 9 [dict get $payload data]
  }
  if { [dict exists $payload raw] && [dict get $payload raw] ne {} } {
    dict set packet_dict 10 [dict get $payload raw]
  }
  if { [dict exists $payload tags] } { dict set packet_dict 11 [dict get $payload tags] }
  if { [dict exists $payload keepalive] } {
    dict set packet_dict 12 [dict get $payload keepalive]
  }
  return [$::cluster::packet::encoder build $packet_dict]
}

proc ::cluster::packet::decode { packet {cluster {}} } {
  try {
    set reader [::bpacket::reader new $packet]
    set result [dict create]
    set results [list]
    set active 1
    while {$active} {
      lassign [$reader next] active id type data
      switch -- $active {
        0 {
          # We are done parsing the packet!
          lappend results $result
          break
        }
        1 {
            # We have more to parse!
            switch -- $id {
            1  {
              lassign $data type channel
              dict set result type $type
              dict set result channel $channel
            }
            2  { dict set result hid $data }
            3  { dict set result sid $data }
            4  { dict set result flags $data }
            5  { dict set result timestamp $data }
            6  { dict set result protocols $data }
            7  { dict set result ruid $data }
            8  { dict set result op $data }
            9  { dict set result data $data }
            10 { dict set result raw $data }
            11 { dict set result tags $data }
            12 { dict set result keepalive $data }
            13 {
              # When we receive a filter we will immediately try to check with the
              # cluster if our service matches and quit decoding immediately if we
              # dont.
              if { $cluster ne {} && ! [$cluster check_filter $data] } { break }
              dict set result filter $data
            }
            14 { dict set result error $data }
          }
        }
        2 {
          # We are done with a packet -- but another might still be
          # available!
          lappend results $result
          set result [dict create]
        }
      }
    }
    $reader destroy
  } on error {result options} {
    #puts stderr "Malformed Packet! $result"
    catch { $reader destroy }
  }
  if { $active } { set result {} }
  return $results
}
