import socket
import json
import math
import time

HOST = "127.0.0.1"
PORT = 5005

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
start_time = time.monotonic()

try:
    while True:
        t = time.monotonic() - start_time
        # 模拟解码后的控制指令
        horizontal = math.sin(t)
        vertical = math.cos(t)
        packet = {
            "horizontal": horizontal,
            "vertical": vertical
        }
        message = json.dumps(packet).encode("utf-8")
        sock.sendto(message, (HOST, PORT))
        print(
            f"Horizontal={horizontal:.2f}, "
            f"Vertical={vertical:.2f}"
        )
        # 每秒发送 20 次
        time.sleep(0.05)
except KeyboardInterrupt:
    print("Control stopped.")
finally:
    sock.close()
