from flask import Flask, request, jsonify
import hashlib
import time
import threading

app = Flask(__name__)

class EndpointNode:
    workQueue = []
    workComplete = []
    maxNumOfWorkers = 0
    numOfWorkers = 0
    sibling = None

    @staticmethod
    def add_sibling(other):
        EndpointNode.sibling = other

    @staticmethod
    def timer_10_sec():
        if EndpointNode.workQueue and time.time() - EndpointNode.workQueue[0]['time'] > 15:
            if EndpointNode.numOfWorkers < EndpointNode.maxNumOfWorkers:
                EndpointNode.spawnWorker()
            else:
                if EndpointNode.sibling and EndpointNode.sibling.TryGetNodeQuota():
                    EndpointNode.maxNumOfWorkers += 1

    @staticmethod
    def TryGetNodeQuota():
        if EndpointNode.numOfWorkers < EndpointNode.maxNumOfWorkers:
            EndpointNode.maxNumOfWorkers -= 1
            return True
        return False

    @staticmethod
    def enqueueWork(text, iterations):
        work = {'text': text, 'iterations': iterations, 'time': time.time()}
        EndpointNode.workQueue.append(work)
        print(f"Work enqueued: {work}")
        return len(EndpointNode.workQueue) - 1

    @staticmethod
    def giveMeWork():
        return EndpointNode.workQueue.pop(0) if EndpointNode.workQueue else None

    @staticmethod
    def pullComplete(n):
        results = EndpointNode.workComplete[:n]
        EndpointNode.workComplete = EndpointNode.workComplete[n:]
        if len(results) > 0:
            return jsonify(results)
        try:
            return EndpointNode.sibling.pullCompleteInternal()
        except:
            return jsonify([])

    @staticmethod
    def pullCompleteInternal():
        results = EndpointNode.workComplete
        EndpointNode.workComplete = []
        return results

    @staticmethod
    def spawnWorker():
        worker = Worker()
        worker.start()

    @staticmethod
    def workComplete(result):
        EndpointNode.workComplete.append(result)
        print(f"Work completed: {result}")

    @staticmethod
    def WorkerDone():
        EndpointNode.numOfWorkers -= 1

class Worker(threading.Thread):
    def __init__(self):
        super().__init__()
        self.buffer = None
        self.iterations = 0

    def DoWork(self, buffer, iterations):
        output = hashlib.sha512(buffer).digest()
        for i in range(iterations-1):
            output = hashlib.sha512(output).digest()
        return output

    def run(self):
        nodes = [EndpointNode, EndpointNode.sibling] if EndpointNode.sibling else [EndpointNode]
        lastTime = time.time()
        while time.time() - lastTime <= 600:  # 10 minutes in seconds
            for node in nodes:
                work = node.giveMeWork()
                if work:
                    # Check if 'work_id' key is present before accessing it
                    if 'work_id' in work:
                        result = self.DoWork(work['text'], work['iterations'])
                        node.workComplete({'work_id': work['work_id'], 'result': result})
                        lastTime = time.time()
                        continue
                    else:
                        # Handle the case when 'work_id' key is missing
                        print("Error: 'work_id' key is missing in the work dictionary")
                time.sleep(0.1)

        EndpointNode.WorkerDone()


@app.route('/enqueue', methods=['PUT'])
def enqueue():
    data = request.get_data()
    iterations = request.args.get('iterations')
    work_id = EndpointNode.enqueueWork(data, int(iterations))
    print(f"Work enqueued with ID: {work_id}")
    return str(work_id)

@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    top = request.args.get('top')
    if top is not None:
        top = int(top)
        return EndpointNode.pullComplete(top)
    else:
        # Handle the case when 'top' is not provided or is invalid
        return jsonify({'error': 'Invalid top value'})



if __name__ == '__main__':
    endpoint = EndpointNode()
    worker = Worker()
    worker.start()
    app.run(host='0.0.0.0', debug=True)
