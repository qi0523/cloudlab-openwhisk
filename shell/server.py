# -*- coding=utf-8 -*-
import socket
import threading
import queue
import sys
import time


# 每个任务线程
class WorkThread(threading.Thread):
    def __init__(self, work_queue):
        super().__init__()
        self.work_queue = work_queue
        self.daemon = True

    def run(self):
        while True:
            func, args = self.work_queue.get()
            func(*args)
            self.work_queue.task_done()


# 线程池
class ThreadPoolManger():
    def __init__(self, thread_number):
        self.thread_number = thread_number
        self.work_queue = queue.Queue()
        for i in range(self.thread_number):     # 生成一些线程来执行任务
            thread = WorkThread(self.work_queue)
            thread.start()

    def add_work(self, func, *args):
        self.work_queue.put((func, args))


def tcp_link(sock, addr):
    print('Accept new connection from %s:%s...' % addr)
    request = sock.recv(1024)
    request = request.decode('utf-8')
    with open("/home/cloudlab-openwhisk/ips.txt", 'a') as f:
        f.write(request + ' ')
    sock.send("OK".encode('utf-8'))
    sock.close()


def start_server(num, local_ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind((local_ip, 3000))
    s.listen(10)
    thread_pool = ThreadPoolManger(100)
    print('listen in %s:%d' % (local_ip, 3000))
    i = 0
    while i < int(num):
        sock, addr = s.accept()
        thread_pool.add_work(tcp_link, *(sock, addr))
        i = i + 1
    time.sleep(3)
    with open("/home/cloudlab-openwhisk/ok.txt", 'a') as f:
        f.write('OK')
    s.close()


if __name__ == '__main__':
    num = sys.argv[1]
    local_ip = sys.argv[2]
    start_server(num, local_ip)
    pass

