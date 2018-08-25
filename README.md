# Alloverse

_By Nevyn Bengtsson (nevyn.jpg@gmail.com), started 2018-08-25._

A VR/AR/3D "window manager" and collaborative workspace.

* Your "place" is where you decorate, run apps, invite people, and
  hang out. It's like a collaborative X11 server: It runs a network
  server, a voip gateway, and all the backing data for 3d UIs for
  the running apps. The base Elixir implementation is in `allo-placeserv`.
* A "visor" is the GUI application you use to visit places and interact
  with your apps. `allo-unityvisor` implements such a visor for VR in Unity.
* An "appliance" is a process running on your computer, or on a computer
  on the Internet. Like opening a web page (or launching a remote X11
  process), this app can then show its interface and be interacted with
  inside your place. 

I'm writing all this from scratch in my barely-available spare time because
it's MY hobby project and ME is an idiot.

## Protocol and implementation ideas

This is still too big for me to wrap my head around, so I'll just start
hacking. But some basic premises:

* A place, a user/visor and appliances are all actors using the same RPC
  mechanic.
* The idea is to use WebRTC as the base transport for free TLS, ICE,
  audio/texture sharing, and data channels with both reliable and unreliable
  transport. 
* For the reliable data channel, I'd _love_ to use my ol erdro protocol,
  a pattern matching-based pub/sub wire protocol.
* The placeserv holds all the state and takes care of all the logic.
  It is the webrtc hub and erdro comms hub. It
    * runs a 10hz game loop,
    * pulses diffs to any actors that want it (primarily visors),
    * is RPC router between actors (place, visors and apps), including app<>app
    * does ACL permission checks on all RPC
    * simulates the physical bodies in the room
    * Manages at least one physical+visual body for each actor.
* I'd love to support different visors: VR, desktop 3D and touch.
* Apps can be spawned in places either by them connecting to the place and
  trying to do an "announce", or by being connected to and prompted to announce.
* Connection is a 2-way HTTPS handshake with the OFFER and ANSWER sdp payloads.
* Except until I implement webrtc, we'll just use TCP.
* `alloverse-place://(https endpoint)...` URLs can be opened to make a visor open a place.
  It performs a standard appliance webrtc handshake, possibly with some authentication
  so that a visor can connect to localhost, or ask permission to join some other
  person's place.
* `alloverse-app://(https endpoint)...` URLs makes a visor ask the open place to connect
  to an app and spawn it in itself.
* Any actor can ask the room to spawn things. So, a basic app could be a web browser
  (streaming its browser texture into VR) showing a portal of `alloverse-app` URLs that
  can be tapped to spawn the app into the place.
* The placeserv ACL ruleset should have a crude editor in v1, something like:
    * predicating on requesting actor (e g allowing anything by place's owner)
    * predicating on action (e g `move` allowed by anyone)
    * predicating on parameter (e g `move` is only allowed at < 1 m/s )
    * action is allow, deny or ask (latter prompting UI to space's owner(s))
* Data:
  * Static data (model/textures/anims/sounds) are attributes of a body, and are sent
    from the owning actor to the place, which then bounces it out to all visors
  * Maybe they can be namespaced and cached...
  * Dynamic textures can be streamed from an actor and bounced out to visors
  * Dynamic audio (e g voip) can be bounced the same way