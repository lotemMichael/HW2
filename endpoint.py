from flask import Flask, request, jsonify
import hashlib
import time
import threading
import subprocess
import requests
import json
from datetime import datetime

app = Flask(__name__)

class EndpointNode:
    workQueue = []
    workComplete = []
    maxNumOfWorkers = 3
    numOfWorkers = 0
    sibling = None
    timer = None
    last_time_spawn_worker = datetime.now()

    @staticmethod
    def add_sibling(other):
        EndpointNode.sibling = other

    @staticmethod
    def timer_10_sec():
        if EndpointNode.workQueue and datetime.now() - EndpointNode.workQueue[0]['time'] > 30:
            if EndpointNode.numOfWorkers < EndpointNode.maxNumOfWorkers:
                EndpointNode.spawnWorker()
            else:
                if EndpointNode.sibling and EndpointNode.sibling.TryGetNodeQuota():
                    EndpointNode.maxNumOfWorkers += 1
        # Schedule the next execution of timer_10_sec
        EndpointNode.timer = threading.Timer(10, EndpointNode.timer_10_sec)
        EndpointNode.timer.start()

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
        try:
            subprocess.run(['bash', 'worker_setup.sh'], check=True)
            EndpointNode.last_time_spawn_worker = datetime.now()
        except subprocess.CalledProcessError as e:
            print(f"Failed to spawn worker: {e}")

    @staticmethod
    def workComplete(result):
        EndpointNode.workComplete.append(result)

    @staticmethod
    def WorkerDone():
        EndpointNode.numOfWorkers -= 1

# routes
@app.route('/enqueue', methods=['PUT'])
def enqueue():
    data = request.get_data()
    iterations = request.args.get('iterations')
    work_id = EndpointNode.enqueueWork(data, int(iterations))
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

@app.route('/addSibling', methods=['POST'])
def add_sibling():
    endpoint = request.args.get('endpoint')
    EndpointNode.add_sibling(endpoint)
    return 'Sibling added successfully'

#Private Routes
@app.route('/internal/pullCompleteInternal', methods=['GET'])
def pull_complete_internal():
    top = int(request.args.get('top'))
    results = EndpointNode.pullCompleteInternal(top)
    return jsonify(results)


@app.route('/internal/giveMeWork', methods=['GET'])
def give_me_work():
    work_item = EndpointNode.giveMeWork()
    if work_item:
        return jsonify(work_item), 200
    else:
        return jsonify({'message': 'No available work'}), 404


@app.route('/internal/sendCompletedWork', methods=['POST'])
def send_completed_work():
    # Get the completed work from the request
    result = request.get_json()
    EndpointNode.workComplete.append(result)
    return 'Completed work added successfully'


@app.route('/internal/TryGetNodeQuota', methods=['GET'])
def try_get_node_quota():
    if EndpointNode.numOfWorkers < EndpointNode.maxNumOfWorkers:
        EndpointNode.maxNumOfWorkers -= 1
        return jsonify(True)
    return jsonify(False)

if __name__ == '__main__':
    endpoint = EndpointNode()
    endpoint.timer_10_sec()
    app.run(host='0.0.0.0', port=5000, debug=True)
