import sys
import requests
import hashlib
import time
import subprocess

class Worker:
    def run(self):
        lastTime = time.time()
        while time.time() - lastTime <= 600:  # 10 minutes in seconds
            for node in nodes:
                work = self.giveMeWork(node)
                if work is not None:
                    result = self.DoWork(work['text'], work['iterations'])
                    self.sendCompletedWork(node, {'work_id': work['work_id'], 'result': result})
                    lastTime = time.time()
                    continue
                time.sleep(0.1)
        subprocess.call(["sudo", "shutdown", "now"])

    def DoWork(self, buffer, iterations):
        output = hashlib.sha512(buffer).digest()
        for i in range(iterations-1):
            output = hashlib.sha512(output).digest()
        return output

    def giveMeWork(self, node):
        url = f"http://{node}/internal/giveMeWork"
        try:
            response = requests.get(url)
            if response.status_code == 200:
                return response.json()
            else:
                print(f"Failed to retrieve work from {node}")
        except requests.exceptions.RequestException as e:
            print(f"An error occurred while querying {node}: {e}")
        return None

    def sendCompletedWork(self, node, result):
        url = f"http://{node}/internal/sendCompletedWork"
        response = requests.post(url, json=result)
        if response.status_code == 200:
            print('Completed work sent successfully')
        else:
            print('Failed to send completed work')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Please provide two node URLs as command-line arguments.")
        sys.exit(1)
    
    nodes = [sys.argv[1], sys.argv[2]]
    worker = Worker()
    worker.run()
