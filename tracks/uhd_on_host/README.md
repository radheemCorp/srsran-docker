docker compose file 
services:
  5gc:
    image: rptestbed/open5gs:v2.7.0-ubuntu22.04-20260417
    # build and other configs remain unchanged...
    container_name: open5gs_5gc
    env_file:
      - ./project-config/open5gs.env
    privileged: true
    ports:
      - "38412:38412/sctp"  # AMF/NGAP
      - "2152:2152/udp"    # UPF/GTP-U
      - "36412:36412/sctp"  # MME/S1AP (Optional)
      - "7777:7777/tcp"    # Healthcheck
    command: 5gc -c open5gs-5gc.yml
    healthcheck:
      test: [ "CMD-SHELL", "nc -z 127.0.0.20 7777" ]
      interval: 3s
      timeout: 1s
      retries: 60
    volumes:
      - ./project-config/subscriber_db.csv:/open5gs/subscriber_db.csv:ro
      - ./project-config/open5gs-5gc.yml.in:/open5gs/open5gs-5gc.yml.in:ro
      
  gnb:
    image: rptestbed/srsran-gnb:ubuntu24.04-uhd-zeromq-20260414
    container_name: srsran_gnb
    privileged: true
    # Use host network mode to avoid MTU/latency issues common with USRPs
    # and to simplify UHD discovery. 
    network_mode: "host" 
    cap_add:
      - SYS_NICE
      - CAP_SYS_PTRACE
      - NET_ADMIN
    volumes:
      # Crucial: Map the entire bus and use consistent paths
      - /dev/bus/usb:/dev/bus/usb
      # Ensure host UHD images match container's expected version or map them
      - /usr/share/uhd/images:/usr/share/uhd/images:ro
      - ./project-config/gnb/gnb_uhd.yml:/gnb_config.yml:ro
      - ./project-config/gnb/gnb_compose_config.yml:/gnb_compose_config.yml:ro
      - ./gnb-storage:/tmp
    command: gnb -c /gnb_config.yml -c /gnb_compose_config.yml
    depends_on:
      5gc:
        condition: service_healthy

volumes:
  gnb-storage: {}


testbed@testbed:~/testbed/srsran-docker/srsRAN_Project/gnb-uhd$ docker compose logs 5gc 
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | RTNETLINK answers: File exists
open5gs_5gc  | Error: ipv4: Address already assigned.
open5gs_5gc  | nc: connect to 127.0.0.1 port 27017 (tcp) failed: Connection refused
open5gs_5gc  | waiting for mongodb
open5gs_5gc  | 
open5gs_5gc  | > open5gs@2.7.0 dev
open5gs_5gc  | > node server/index.js
open5gs_5gc  | 
open5gs_5gc  | > Using external babel configuration
open5gs_5gc  | > Location: "/open5gs/webui/.babelrc"
open5gs_5gc  |  DONE  Compiled successfully in 493ms1:24:58 PM
open5gs_5gc  | 
open5gs_5gc  | Mongoose: subscribers.ensureIndex({ imsi: 1 }, { unique: true, background: true })
open5gs_5gc  | Mongoose: accounts.ensureIndex({ username: 1 }, { unique: true, background: true })
open5gs_5gc  | (node:95) DeprecationWarning: collection.ensureIndex is deprecated. Use createIndexes instead.
open5gs_5gc  | (Use `node --trace-deprecation ...` to show where the warning was created)
open5gs_5gc  | Mongoose: accounts.count({}, {})
open5gs_5gc  | (node:95) DeprecationWarning: collection.count is deprecated, and will be removed in a future version. Use Collection.countDocuments or Collection.estimatedDocumentCount instead
open5gs_5gc  | > Ready on http://testbed:9999
open5gs_5gc  | Mongoose: accounts.findOne({ '$or': [ { username: 'admin' } ] }, { projection: { hash: 0, salt: 0 } })
open5gs_5gc  | Connection to 127.0.0.1 27017 port [tcp/*] succeeded!
open5gs_5gc  | Mongoose: accounts.insertOne({ roles: [ 'admin' ], _id: ObjectId("69e75e8aca9349005fd87cbc"), username: 'admin', salt: 'e11b5af0874bcab9955e63bc0bd1447a17112c49ba3db03e0e10bbee9ca31ae7', hash: 'b0485d7a9778ffaac81aa21eccf6278f382ce447a21c0cf7c5cf07bfae1cb05ea04861bf0a2594ad0cae1441a88d65cf054e8984d65be577e7c42db3d2d9e8e1a9c9c531341994492a02c1161d8c0ae710b0ea50c3ffaa62ed4248e3589aecf95837c1de15ee569cff0cff4065025e3e2d7a6de500198d3062a5983dcf792dbf88854cd5f6c1a685ee89b5ea3234e5a7a18aa968258e8082eb164d2fb0976d4393bdf28329f9be56671136c11c9837df09f62066e60d17c207f2fdb4caa3ae4234f1e663a3b77e6555eec14b96a27318a9d17c41d687a4ba285882be5d201b3b65b45880625e52b036cbbf08182f6c9ee0b493b9ae5b8d6ea6e36d652883e868895abc7a33fe8c5fc05eda1883849395ebd63029fc17a1b0c73e69ccc7f3604ff293932c958010100429917e4f16b34fbb4e5ce4aa956dcea351ea504191e1b81c55dcba5cf8ac08d97e7ccc3d12e8a6bc07d05d667ce26f68d0f547b7ce655e3d107370619adf8b77ffde3e0c537ff3b5dc25e49b564c96fa9b31f84f2ba228a56854ad336638744e4da8a868981e3861301cc97d804897c19e9fbe990d4b240981b66d6eca2dacee3cb9a34f42b40f4423ca6388126f6e9e39709762f2d9e35d3e208a1162948d266dcfa948d17684c15c7997027b12f717a0f319a5fc7683fedafe3188cc21756a703893ab9d8a1bfe3fcf6e2d2dcf544be54fecf2fc8f64', __v: 0}, { session: null })
open5gs_5gc  | Traceback (most recent call last):
open5gs_5gc  |   File "/open5gs/setup_tun.py", line 79, in <module>
open5gs_5gc  |     main()
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/click/core.py", line 1485, in __call__
open5gs_5gc  |     return self.main(*args, **kwargs)
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/click/core.py", line 1406, in main
open5gs_5gc  |     rv = self.invoke(ctx)
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/click/core.py", line 1269, in invoke
open5gs_5gc  |     return ctx.invoke(self.callback, **ctx.params)
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/click/core.py", line 824, in invoke
open5gs_5gc  |     return callback(*args, **kwargs)
open5gs_5gc  |   File "/open5gs/setup_tun.py", line 61, in main
open5gs_5gc  |     ipr.addr('add', index=dev, address=first_ip_addr, mask=ip_netmask)
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/pyroute2/iproute/linux.py", line 2799, in _run_generic_rtnl
open5gs_5gc  |     return self._run_with_cleanup(func, *argv, **kwarg)
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/pyroute2/netlink/core.py", line 813, in _run_with_cleanup
open5gs_5gc  |     return self.asyncore.event_loop.run_until_complete(
open5gs_5gc  |   File "/usr/lib/python3.10/asyncio/base_events.py", line 649, in run_until_complete
open5gs_5gc  |     return future.result()
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/pyroute2/iproute/linux.py", line 2040, in addr
open5gs_5gc  |     return [x async for x in request.response()]
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/pyroute2/iproute/linux.py", line 2040, in <listcomp>
open5gs_5gc  |     return [x async for x in request.response()]
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/pyroute2/netlink/nlsocket.py", line 664, in response
open5gs_5gc  |     async for msg in coro:
open5gs_5gc  |   File "/usr/local/lib/python3.10/dist-packages/pyroute2/netlink/core.py", line 575, in get
open5gs_5gc  |     raise error
open5gs_5gc  | pyroute2.netlink.exceptions.NetlinkError: (17, 'File exists')
open5gs_5gc  | Failed to setup ogstun and routing
testbed@testbed:~/testbed/srsran-docker/srsRAN_Project/gnb-uhd$ 