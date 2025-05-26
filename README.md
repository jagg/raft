# Toy Raft

This is my toy Raft implementation, backing an key-value store. Still work in progress!

## How to test it

For now, just run a few servers from different terminals, with their
own cluster.conf files, and watch them negotiate who will be the
leader!

> $ ./_build/default/bin/main.exe -p 5555 -o 7771 -i "one" -f cluster.conf

> $ ./_build/default/bin/main.exe -p 5556 -o 7772 -i "two" -f cluster2.conf

> $ ./_build/default/bin/main.exe -p 5557 -o 7773 -i "three" -f cluster3.conf
