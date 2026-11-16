# BCR J-2 field mapping (adapter-owner review)

The B adapter owner supplied and reviewed this field inventory during J-2.
It records intended projections; host adoption and source pins are tracked in
the workspace review. All `at` fields use injected monotonic host time, never Date as a neutral clock.

| Existing type/field | Neutral destination or adapter-only reason |
|---|---|
| MIDIControlKind.controlChange/note/nrpn | adapter-only protocol syntax; mapped logical element determines InputCapability.kind |
| MIDIControlID.kind | adapter-only protocol syntax |
| MIDIControlID.channel | adapter-only MIDI address |
| MIDIControlID.number | adapter-only MIDI address; HardwareMap resolves elementID, never encode numeric MIDI address into Kit data |
| MIDIControlID.description | adapter-only localized protocol UI text |
| MIDIVoiceMessage.nrpn(channel,number,value) | channel/number stay adapter; decoded value → DeviceValue.number(Double(value)) on neutral input/effect (not business quantization) |
| MIDIVoiceMessage.controlChange(channel,number,value) | channel/number stay adapter; value → number, kind absolute/relative/press/release determined by learned control policy |
| MIDIVoiceMessage.noteOn(channel,number,velocity) | channel/number stay adapter; decoded button press/release → DeviceInputEvent.kind and .flag; raw velocity stays wire capture |
| MIDIVoiceMessage.noteOff(channel,number,velocity) | channel/number/velocity stay wire capture; release → InputKind.release/.flag(false) |
| MIDIVoiceMessage.controlID | adapter resolver input; output targetID is logical display target |
| MIDIVoiceMessage.value | seven-bit UI projection remains adapter; avoid turning it into a second authoritative value |
| MIDIVoiceMessage.dataValue | exact decoded raw value feeds number; no normalization/quantization in Kit |
| MIDIVoiceMessage.maximumDataValue | protocol capacity stays adapter; ElementCapability only states number/flag kind |
| MIDIVoiceMessage.isPositiveActivation | learned protocol/press semantics stay adapter, resolved neutral press/release emitted after decoding |
| MIDIVoiceMessage.diagnosticDescription | localized device diagnostics stays adapter |
| MIDIVoiceMessage.midi1Bytes | wire encoding stays adapter; never enters neutral effect |
| MIDI1UMPCodec | every function adapter-only: packet word count, decode/encode, group nibble, feedback/feedback14 are MIDI protocol knowledge |
| MIDIEncodingError.invalidMessage/requiresMultipleWords | adapter failure; trace rejection reason is semantic string, not Kit MIDI enum |
| NRPNAssembler.channels | adapter-only fragment state; Kit consumes complete logical events |
| NRPNAssembler.Selection.msb | adapter MIDI selector fragment |
| NRPNAssembler.Selection.lsb | adapter MIDI selector fragment |
| NRPNAssembler.Selection.dataMSB | adapter MIDI data fragment |
| NRPNAssembler.Selection.date | adapter fragment expiry clock (existing Date injection), no neutral system-clock read |
| DeviceSource.mock | SurfaceDeviceContracts.DeviceSource.simulation |
| DeviceSource.hardware | SurfaceDeviceContracts.DeviceSource.hardware |
| DeviceSource.id | adapter UI identity, same raw source projection above |
| HardwareOutputPolicy.observe/write | adapter direction authorization; cannot become optional device-safety switch in Kit |
| MIDIConnectionSnapshot.sourceEndpoints | adapter inventory; selected endpoint gives EndpointProvenance, full native inventory stays adapter |
| MIDIConnectionSnapshot.destinationEndpoints | same as sourceEndpoints, output direction distinct |
| MIDIConnectionSnapshot.transportGeneration | EndpointProvenance.connectionGeneration (UInt64 exact conversion) |
| MIDIConnectionSnapshot.connectedSourceID | EndpointProvenance.endpointID for input, String(Int32) if known |
| MIDIConnectionSnapshot.connectedDestinationID | EndpointProvenance.endpointID for output, String(Int32) if known |
| MIDIConnectionSnapshot.sourceNames/destinationNames | UI labels stay adapter; never infer transport origin |
| MIDIConnectionSnapshot.connectedSource/connectedDestination | UI labels/readiness stay adapter; neutral context identifies opaque route, not name |
| MIDIConnectionSnapshot.lastError | adapter diagnostic; failing trace may use reason, no global mutable Kit error owner |
| MIDIConnectionSnapshot.isConnected | adapter determines lifecycle fact; J2 does not introduce connection reducer |
| MIDIConnectionSnapshot.hasSameRoute | adapter route comparison; J3 separately audits old-generation invalidation |
| SurfaceDevice.connection | adapter port state; native object lifetime never in Kit |
| SurfaceDevice.onMessages | adapter callback only; decode → immutable DeviceInputEvent at host boundary |
| SurfaceDevice.onConnection | adapter callback only; J3 value reducer later, not J2 |
| SurfaceDevice.send | adapter IO only; EffectDescriptor + TransmissionEvidence describe before/after without doing IO |
| MockSurfaceDevice.model | simulation device model stays adapter, not business authority in Kit |
| MockSurfaceDevice.connection | adapter simulation route; neutral source simulation. Known localVirtual provenance is retained even if endpoint identity is nil; no fabricated ID or qualification |
| MockSurfaceDevice.onMessages/onConnection | same adapter callback mapping as SurfaceDevice |
| MockSurfaceDevice.model.encoderModes (configureModes) | learned/Mock protocol behavior stays adapter |
| MockSurfaceDevice.model.activeGroup (selectGroup) | group stays adapter; opaque context id/revision projects into DeviceContext |
| MockSurfaceDevice methods send/setNRPN/resetInputState/turn/move/applyCapturedInput/emit/press/release | pure simulator/device protocol code stays adapter; complete input/observed/send facts cross neutral boundary only |
| SurfaceInputBatch.messages | each resolved native message → DeviceInputEvent; packet decoding/NRPN assembly stays adapter |
| SurfaceInputBatch.endpoint | EndpointProvenance exactly; never reconstruct from current route |
| SurfaceInputObserving.onInputBatch | adapter callback; neutral API remains synchronous Sendable values |
| MIDIEndpointDescriptor.id | EndpointProvenance.endpointID |
| MIDIEndpointDescriptor.name | adapter presentation only |
| MIDIEndpointDescriptor.availabilityKnown | native enumeration evidence stays adapter, never become permission/qualification |
| MIDIEndpointDescriptor.provenance | EndpointProvenance.transportOrigin exact enum mapping |
| MIDIEndpointSource.endpointID | EndpointProvenance.endpointID; existing unknown sentinel requires explicit nil/unknown mapping (must not silently invent identity) |
| MIDIEndpointSource.deviceID | EndpointProvenance.deviceID, nil preserved |
| MIDIEndpointSource.connectionGeneration | exact same UInt64 |
| MIDIEndpointSource.provenance | transportOrigin exact mapping |
| MonitorEvent.id | trace step/effect correlation identifier; native ordering retained |
| MonitorEvent.time | audit/UI wall-clock stays adapter |
| MonitorEvent.monotonicTime | neutral input/observation/transmission at |
| MonitorEvent.direction | input→DeviceInputEvent; output→EffectDescriptor/TransmissionEvidence distinct |
| MonitorEvent.source | .mock→simulation; .hardware→hardware |
| MonitorEvent.message | decoded logical payload maps, raw MIDI stays adapter |
| MonitorEvent.control | logical opaque elementID through existing stable ID encoder |
| MonitorEvent.ignored | trace accepted/rejected metric; ignored raw packet must not become accepted DeviceObservation |
| MonitorEvent.origin | trusted caller identity remains adapter authorization; not a transport source override |
| MonitorEvent.delivery | .sent from an actual transport acceptance→TransmissionOutcome.accepted; an actual failed send→rejected reason. Pre-I/O suppression/disconnection is a ShadowDecision with no invented transport call/evidence; never observation evidence |
| MonitorEvent.endpoint | neutral provenance captured at original receipt/send |

Supervisor ruling: unknown endpoint/device identity remains nil while independently
known transport provenance is retained. The previous proposed requirement for a
non-unknown origin to have an endpoint ID was rejected; provenance carries facts,
not routing permission or hardware qualification. An adapter still needs its own
valid current route before any actual send. No name-based identity or fabricated
ID is permitted.

Neutral capabilities express logical features only; protocol ranges, group
counts, LED modes, BCL transactions, Quick Learn and hardware qualification stay
adapter-owned. Internal native fields remain available for codec/capture/GUI; no
field is silently dropped as a way to pass a shadow comparison.
