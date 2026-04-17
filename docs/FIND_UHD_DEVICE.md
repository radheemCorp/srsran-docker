# isntallation 

```bash 
sudo apt update
sudo apt install libuhd-dev uhd-host -y
sudo /usr/lib/uhd/utils/uhd_images_downloader.py
```

# find device 
```bash
uhd_find_devices
```


# benchmark 
```bash 
/usr/lib/uhd/examples/benchmark_rate --args="type=b200" --duration 10 --rx_rate 23.04e6 --tx_rate 23.04e6
```