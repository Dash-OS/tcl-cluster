# tcl cluster

**UNFINISHED (But Working)**

`cluster` is a tcl package which provides a simple light-weight framework for
providing inter-process and inter-machine discovery and communications.  

`cluster`'s evaluation hooks provide powerful extensibility, allowing the programmer to modify 
the general behavior of a cluster to fit their security and/or communications handling needs.

**Package Dependencies**

- [TclUDP](https://sourceforge.net/projects/tcludp/) Extension (v1.0.11 or higher)

**Supported Platforms**

- Linux / Unix
  - Requires [tuapi](http://chiselapp.com/user/rkeene/repository/tuapi/home)

It is actually relatively easy to support other platforms or not require tuapi.  Just need
to modify a few of the initial procs to give data such as LAN IP's and MAC Address.

## Key Concepts

`cluster` aims to provide a lightweight modular framework for cluster discovery, communications, 
and coordination.  `cluster` members automatically discover each other and provide its preferred 
protocols for communication.  

In a local environment, it's as simple as having both run `[cluster join]` and awaiting 
discovery.  We can then pass messages and commands between our cluster members.

#### Local and/or Remote Capable

By default, our beacons will be set with a UDP TTL of 0.  This means that our beacons 
will only be heard locally on the system.  We may set the ttl value used by our beacons 
using the `-remote` configuration parameter.  Anything higher than 0 will begin to open
our beacons further out from the machine.

When `-remote` is set to 0, communications will be ignored from any communications originating 
from outside of our localhost.  You may also use hooks to provide this type of security based on 
the context of the cluster.

#### Customizable & Extendable

#### Custom Protocol Handlers

## Quick Example

Below we see a simple example of using cluster where we simply join the cluster
and register a hook to inform us whenever a new service has been discovered.

Running this on two different shells (on the same system for now), you should
see the two shells discovered each other.

```tcl

package require cluster
set cluster [cluster join -tags [list service_one]]

$cluster hook service discovered {
  puts "New Service Discovered: $service"
}

# Enter the event loop and allow cluster to work
vwait _forever_

```

```tcl

package require cluster
set cluster [cluster join -tags [list service_two]]

$cluster hook service discovered {
  puts "New Service Discovered: $service"
}

# Enter the event loop and allow cluster to work
vwait _forever_

```


## Hooks

Hooks provide a means to customize the evaluation environment with ***short snippets of 
mutations and additions*** to the regular lifecycle of the package.  Hooks are always 
evaluated within the hooks given context.  

We can modify the behavior at each level by either changing values before they are sent 
or received, or throwing an error to cancel any further handling.


#### `$cluster hook evaluate send`

#### `$cluster hook evaluate receive`

### Channel Hooks

#### `$cluster hook channel receive <channels>`

### Evaluate Hooks

#### `$cluster hook evaluate service`

#### `$cluster hook evaluate receive`

#### `$cluster hook evaluate send`

> Called right after the 

### Protocol Hooks

#### `$cluster hook protocol <proto> receive`

#### `$cluster hook protocol <proto> send`

### Op Hooks

#### `$cluster hook op <op> receive`

#### `$cluster hook op <op> send`

### Service Hooks

#### `$cluster hook service eval`

#### `$cluster hook service validate`

#### `$cluster hook service found`

#### `$cluster hook service lost`


# cluster-comm
# cluster-comm
