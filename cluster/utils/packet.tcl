package require bpacket

namespace eval ::cluster {}
namespace eval ::cluster::packet {}

if 0 {
  @ io handler
    Here we create a [bpacket] io object which
    is capable of encoding and decoding our packets
    based upon the template below.
}
bpacket create io ::cluster::packet::io {
  1  varint  type
  2  varint  channel
  3  string  hid
  4  string  sid
  5  varint  known
  6  varint  timestamp
  7  list    protocols
  8  string  ruid
  9  string  op
  10 string  data
  11 raw     raw
  12 list    tags
  13 boolean keepalive
  14 list    filter
  15 string  error
}

proc ::cluster::packet::encode payload {
  set encoded [io encode $payload]
  return $encoded
}

if 0 {
  @ cluster packet decode
    When we receive an encoded packet, we will decode it.  We use the
    -validate option here so that we can cancel the decoding process
    early so that we do not need to decode an entire packet just to
    know that we are going to ignore it later.

    cluster
}
proc ::cluster::packet::decode { packet {cluster {}} } {
  set decoded [io decode $packet \
    -validate [list ::apply {
      {cluster field} {
        # break        - stop parsing, return packet as is
        # continue     - do not include field
        # return false - stop parsing, return empty packet
        # error        - throw given error
        # else         - add field to packet by name and id
        # notes:
        #   - modify field with   upvar field   if needed
        #   - modify results with upvar results if needed
        switch -- [dict get $field id] {
          4  {
            # sid
            if {$cluster eq {} || [dict get $field value] eq [$cluster sid]} {
              # if we receive a sid and it appears to come from us,
              # stop parsing the packet
              return 0
            }
          }
          14 {
            # filter
            if {$cluster ne {} && ! [$cluster check_filter [dict get $field value]]} {
              # check the filter and only continue if we match
              return 0
            }
          }
        }
      }
    } $cluster]
  ]

  # puts "Decoded Packet:"
  # puts $decoded

  return $decoded
}
