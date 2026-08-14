# Chunk 3 — Context

Everything needed to port the packetiser. **Read this instead of the Python sources.**

### idotmatrix/const.py (relevant constants)

```python
UUID_CHARACTERISTIC_WRITE_DATA = "0000fa02-0000-1000-8000-00805f9b34fb"
UUID_READ_DATA                 = "0000fa03-0000-1000-8000-00805f9b34fb"
BLUETOOTH_DEVICE_NAME          = "IDM-"
```

### idotmatrix/modules/gif.py:21-22

```python
CHUNK_SIZE_4096 = 4096
HEADER_SIZE_GIF = 16  # As per sendImageData logic in GifAgreement.java
```

### idotmatrix/modules/gif.py:211-294 — create_gif_data_packets

Returns a list of lists: outer = 4K chunks with headers, inner = BLE packets.

```python
def create_gif_data_packets(self, gif_data, gif_type, time_sign,
                            ble_device_mtu_enabled=True):
    send_data_3 = []
    if not gif_data:
        raise ValueError("gif_data cannot be empty or None.")

    crc32_val = self.calculate_crc32_java_equivalent(gif_data)
    crc32_bytes = self._int_to_bytes_le(crc32_val)            # 4 bytes LE
    total_length_bytes = self._int_to_bytes_le(len(gif_data))  # 4 bytes LE

    chunks_4096 = self._chunk_data_by_size(gif_data, CHUNK_SIZE_4096)

    processed_large_packets_with_headers = []
    for i, current_chunk in enumerate(chunks_4096):
        packet_data_length = len(current_chunk) + HEADER_SIZE_GIF
        packet_data_length_bytes_be = bytearray(
            self._int_to_bytes_le(packet_data_length))

        header = bytearray(HEADER_SIZE_GIF)
        header[0] = packet_data_length_bytes_be[0]   # length, low byte
        header[1] = packet_data_length_bytes_be[1]   # length, high byte
        header[2] = 1
        header[3] = 0
        header[4] = 2 if i > 0 else 0                # continuation flag
        header[5:9]  = total_length_bytes[0:4]       # total GIF length, LE
        header[9:13] = crc32_bytes[0:4]              # CRC32, LE

        if gif_type == 12:
            header[13] = 0
            header[14] = 0
        else:
            converted = self._convert_device_material_time(time_sign)
            tsb = bytearray(converted.to_bytes(2, byteorder='big'))
            header[13] = tsb[0]
            header[14] = tsb[1]

        header[15] = gif_type & 0xFF

        processed_large_packets_with_headers.append(bytes(header) + current_chunk)

    for large_packet in processed_large_packets_with_headers:
        ble_packets_for_chunk = self._create_ble_packets(
            large_packet, ble_device_mtu_enabled)
        if ble_packets_for_chunk:
            send_data_3.append(ble_packets_for_chunk)

    return send_data_3
```

**Note:** despite the variable name saying "BE", `_int_to_bytes_le` is little-endian
and only bytes [0] and [1] are used, so the length field is a 16-bit little-endian
value. Port exactly this behaviour, including that quirk.

### idotmatrix/modules/gif.py:296-315 — _create_ble_packets

```python
@staticmethod
def _create_ble_packets(data_packet, ble_device_mtu_enabled=True):
    if not data_packet:
        return []
    ble_packets = []
    mtu_packet_size = 509 if ble_device_mtu_enabled else 18
    num_ble_packets = (len(data_packet) + mtu_packet_size - 1) // mtu_packet_size
    for i in range(num_ble_packets):
        start = i * mtu_packet_size
        end = min((i + 1) * mtu_packet_size, len(data_packet))
        ble_packets.append(bytearray(data_packet[start:end]))
    return ble_packets
```

### Helpers

```python
def _int_to_bytes_le(self, value, length=4):
    return bytearray(value.to_bytes(length, byteorder="little"))

def _chunk_data_by_size(self, data, chunk_size):
    return [data[i:i + chunk_size] for i in range(0, len(data), chunk_size)]

def calculate_crc32_java_equivalent(self, data):
    # standard zlib/binascii CRC32, unsigned
    return binascii.crc32(data) & 0xFFFFFFFF
```

### Call site (what the app must reproduce)

```python
packets = self.create_gif_data_packets(gif_data=gif_data, gif_type=12, time_sign=1)
await self._send_packets(packets=packets, response=True)
```

`gif_type=12` is what the daemon uses, so the `time_sign` branch is never taken —
implement it anyway for fidelity, but the golden fixtures only exercise type 12.

### Known-good numbers

For a 550-byte GIF: 1 outer chunk, 566 bytes with header, **2** BLE packets
(509 + 57). Use this as a sanity check while developing.
