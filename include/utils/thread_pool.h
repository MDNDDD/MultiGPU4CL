/*this is from https://github.com/progschj/ThreadPool 

an explanation: https://www.cnblogs.com/chenleideblog/p/12915534.html
*/

#ifndef THREAD_POOL_H
#define THREAD_POOL_H
#pragma once

#include <vector>
#include <queue>
#include <memory>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <future>
#include <functional>
#include <stdexcept>

class ThreadPool {
public:
    ThreadPool(size_t); // Constructor of the thread pool
    template<class F, class... Args>
    auto enqueue(F&& f, Args&&... args) 
        -> std::future<typename std::result_of<F(Args...)>::type>; // Add a task to the thread pool's task queue
    ~ThreadPool(); // Destructor of the thread pool
private:
    // need to keep track of threads so we can join them
    std::vector< std::thread > workers; // Array for storing threads, saved in a vector container
    // the task queue
    std::queue< std::function<void()> > tasks; // Queue for storing tasks, saved in a queue container. Task type is std::function<void()>. Since std::function is a general-purpose polymorphic function wrapper, the task queue essentially stores individual functions
    
    // synchronization
    std::mutex queue_mutex; // A mutex for accessing the task queue; both inserting tasks and threads fetching tasks require the mutex for safe access
    std::condition_variable condition; // A condition variable for notifying threads about the task queue state; if there are tasks, threads are notified to execute, otherwise they enter wait state
    bool stop; // Flag indicating the thread pool state, used during construction and destruction to track the pool's status
};
 
// the constructor just launches some amount of workers
inline ThreadPool::ThreadPool(size_t threads) // Constructor defined as inline. The parameter threads indicates how many threads to create in the pool.
    :   stop(false) // stop is initialized to false, meaning the thread pool is running.
{
    for(size_t i = 0;i<threads;++i) // Enter for loop, create threads one by one and place them into the workers array.
        workers.emplace_back( 
            /*
            In vector, emplace_back() inserts an object at the end of the container, with the same effect as push_back(),
            but with a slight difference: emplace_back(args) takes the object's constructor arguments, while push_back(OBJ(args))
            takes the object itself. That is, emplace_back() directly constructs a new object in the container using the passed
            arguments, whereas push_back() first constructs a temporary object and then copies it into the container's memory.
            
            The format of a lambda expression is:
            [ capture ] ( parameters ) specifier(optional) exception attr -> return type { function body }
            So the lambda expression below is of the [ capture ] { function body } type. The passed lambda expression serves as
            the execution function for thread creation.       
            */
            [this] // This lambda expression captures the thread pool pointer 'this' for use in the function body (accessing member variables stop, tasks, etc.)    
            {
                for(;;) // for(;;) is an infinite loop, meaning each thread will repeatedly execute this way; this is how all threads in a thread pool behave.
                {
                    std::function<void()> task; // In the loop, first create a std::function<void()> object task to receive the actual task popped from the task queue.

                    {
                        std::unique_lock<std::mutex> lock(this->queue_mutex); // Within this {}, queue_mutex is locked

                        /*This means that if the thread pool has stopped or the task queue is not empty, it will not enter the wait state.
                          Since the thread pool is just created, it is not stopped and the task queue is empty, so every thread enters the wait state.
                          If a condition variable notification arrives later, the thread will continue execution.
                        */
                        this->condition.wait(lock,
                            [this]{ return this->stop || !this->tasks.empty(); });

                        /*If the thread pool has stopped and the task queue is empty, return; i.e., all threads break out of the infinite loop
                          and exit the pool. Before this, each thread is either in wait state or executing the task below.*/
                        if(this->stop && this->tasks.empty())
                            return;

                        /*
                        Mark the first task in the task queue with task, then pop that task from the queue.
                        (This is done while the thread holds the mutex for the task queue. After the condition variable wakes the thread,
                        the thread will only continue execution within the wait cycle after acquiring the mutex for the task queue.
                        Therefore, only one thread will get the task, and no thundering herd effect will occur.)
                        After exiting {}, the lock on the task queue is released, and the thread can execute the fetched task.
                        After execution, the thread re-enters the infinite loop.
                        */
                        task = std::move(this->tasks.front());
                        this->tasks.pop(); // Tasks do not accumulate in the queue
                    }

                    task();
                }
            }
        );
}

// add new work item to the pool
/*
enqueue is a template function with type parameters F and Args. class... Args represents multiple type parameters.
auto is used to automatically deduce the return type of enqueue. The function parameters are (F&& f, Args&&... args),
where && denotes rvalue reference, accepting an F-type f and several Args-type args.

typename std::result_of<F(Args...)>::type   // Get the return type of function F with Args as parameters
std::future<typename std::result_of<F(Args...)>::type> // std::future is used to access the result of an asynchronous operation
Ultimately, it returns the asynchronous execution result of F(Args...) wrapped in std::future.
*/
template<class F, class... Args>
auto ThreadPool::enqueue(F&& f, Args&&... args) 
    -> std::future<typename std::result_of<F(Args...)>::type> // Indicates the return type, same as the notation used in lambda expressions.
{
    using return_type = typename std::result_of<F(Args...)>::type; // Get the return type of function F with Args as parameters

    auto task = std::make_shared< std::packaged_task<return_type()> >(
            std::bind(std::forward<F>(f), std::forward<Args>(args)...)
        );
        
    std::future<return_type> res = task->get_future(); // res holds a variable of type return_type; the value can only be saved after the task finishes asynchronous execution
    {
        std::unique_lock<std::mutex> lock(queue_mutex);

        // don't allow enqueueing after stopping the pool
        if(stop)
            throw std::runtime_error("enqueue on stopped ThreadPool");

        tasks.emplace([task](){ (*task)(); });
    }
    condition.notify_one(); // After a task is added to the task queue, a thread needs to be woken up
    return res; // After the thread finishes execution, return the result
}

// the destructor joins all threads
inline ThreadPool::~ThreadPool()
{
    /*
    In the destructor, first lock the task queue, then set the stop flag to true,
    so that any subsequent task insertion operations will fail.
    */
    {
        std::unique_lock<std::mutex> lock(queue_mutex); // Within this {}, queue_mutex is locked
        stop = true;
    }
    /*Use the condition variable to wake up all threads; all threads will proceed*/
    condition.notify_all();

    /*When stop is set to true and the task queue is empty, the corresponding thread breaks out of the loop and exits.
    Set each thread to join, and wait for all threads to finish before the main thread exits.*/
    for(std::thread &worker: workers)
        worker.join();
}

#endif



/*Example:

#include <iostream>
#include <tool_functions/ThreadPool.h>
using namespace std;

class example_class
{
public:
    int a;
    double b;
};
example_class example_function(example_class x)
{
    return x;
}

void ThreadPool_example()
{
    ThreadPool pool(4);	// Create a thread pool with 4 threads
    std::vector<std::future<example_class>> results; // return typename: example_class; save multi-thread execution results
    for (int i = 0; i < 10; ++i)
    { // Create 10 tasks
        int j = i + 10;
        results.emplace_back(  // Save each asynchronous result
            pool.enqueue([j] { // Add each task to the task queue; lambda expression: pass const type value j to thread; [] can be empty
                example_class a;
                a.a = j;
                return example_function(a); // return to results; the return type must be the same with results
            }));
    }
    for (auto &&result : results)			// Retrieve results saved in results one by one
        std::cout << result.get().a << ' '; // result.get() makes sure this thread has been finished here;
    results.clear(); // future get value can only be called once. After get(), the future in results can no longer be used; after clear(), results can be used again
    std::cout << std::endl;
    // if result.get() is pair<int, string>, then you cannot use result.get().first = result.get().second
}

int main()
{
    ThreadPool_example();
}

*/



/*Example: multi_thread write a vector (use std lock mechanism)  


#include <iostream>
#include <tool_functions/ThreadPool.h>
#include <mutex>
using namespace std;

int vector_size = 3;
vector<vector<int>> vectors(vector_size);
vector<std::mutex> mtx(vector_size); // Protect vectors
void thread_function(int ID, int value)
{
    mtx[ID].lock(); // only one thread can lock mtx[ID] here, until mtx[ID] is unlocked
    vectors[ID].push_back(value);
    mtx[ID].unlock();
}
void ThreadPool_example()
{
    ThreadPool pool(5);	// use 5 threads
    std::vector<std::future<int>> results; // return typename: xxx
    for (int i = 0; i < vector_size; ++i)
    {
        for (int j = 0; j < 1e1; j++)
        {
            results.emplace_back(
                pool.enqueue([i, j] { // pass const type value j to thread; [] can be empty
                    thread_function(i, j);
                    return 1; // return to results; the return type must be the same with results
                }));
        }
    }
    for (auto &&result : results)
        result.get(); // all threads finish here
    for (int i = 0; i < vector_size; ++i)
    {
        cout << "vectors[" << i << "].size(): " << vectors[i].size() << endl;
        for (int x = 0; x < vectors[i].size(); x++)
        {
            std::cout << vectors[i][x] << ' ';
        }
        std::cout << std::endl;
    }
}
int main(){ThreadPool_example();}


*/
