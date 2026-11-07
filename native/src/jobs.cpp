// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See jobs.h. The pool is the module's own threads (std::thread, the owner's choice of
// 2026-11-07 over the engine's WorkerThreadPool: a loop's spans start without a round through the
// engine's task queue, and the workers are not shared with the engine's own tasks). They are made
// the first time a loop asks for them, so a game that never runs a wide loop makes none.
//
// One loop runs at a time, from the thread that steps the game. Its handshake is under one
// mutex: the caller publishes the loop and bumps `generation`; each worker it asked for takes the
// loop's numbers under the lock, claims chunks from the shared counter until none is left, and
// checks out (`checked_out`). The caller runs chunks too, then waits until every chunk is done
// and every worker it asked for checked out, so no worker can still be reading this loop's
// numbers when the next one is published. A worker sleeps between loops: one that spun there
// (tried 2026-11-07) slowed the thread stepping the game more than its quicker start saved.

#include "jobs.h"

#ifdef THREADS_ENABLED
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>
#endif

namespace jobs {

namespace {

// Runs every chunk on the calling thread.
void run_here(int64_t chunks, void (*body)(void *, int64_t), void *context) {
	for (int64_t i = 0; i < chunks; i++) {
		body(context, i);
	}
}

} // namespace

#ifdef THREADS_ENABLED

namespace {

// How many times the caller looks again (giving up its turn between) for its loop's last chunks
// before it sleeps until they are done.
constexpr int SPINS = 2000;

struct Pool {
	std::mutex lock;
	std::condition_variable wake;
	std::condition_variable finished;
	std::vector<std::thread> workers;
	// Bumped for each loop.
	uint64_t generation = 0;
	bool stopping = false;
	// The loop running now. All of the above and `checked_out` are under `lock`.
	void (*body)(void *, int64_t) = nullptr;
	void *context = nullptr;
	int64_t chunks = 0;
	int helpers = 0;
	std::atomic<int64_t> next{ 0 };
	std::atomic<int64_t> done{ 0 };
	int checked_out = 0;
	// Whether a loop runs: one asked for meanwhile (a body's own) runs on its caller alone.
	std::atomic<bool> busy{ false };

	// Claims and runs chunks until none is left.
	void work(void (*b)(void *, int64_t), void *c, int64_t n) {
		int64_t ran = 0;
		for (int64_t i = next.fetch_add(1, std::memory_order_relaxed); i < n; i = next.fetch_add(1, std::memory_order_relaxed)) {
			b(c, i);
			ran += 1;
		}
		if (ran > 0) {
			done.fetch_add(ran, std::memory_order_acq_rel);
		}
	}

	void worker(int index) {
		uint64_t seen = 0;
		for (;;) {
			void (*b)(void *, int64_t) = nullptr;
			void *c = nullptr;
			int64_t n = 0;
			{
				std::unique_lock<std::mutex> held(lock);
				wake.wait(held, [&] { return stopping || generation != seen; });
				if (stopping) {
					return;
				}
				seen = generation;
				if (index >= helpers) {
					continue;
				}
				b = body;
				c = context;
				n = chunks;
			}
			work(b, c, n);
			{
				std::lock_guard<std::mutex> held(lock);
				checked_out += 1;
			}
			finished.notify_one();
		}
	}

	void run(int64_t n, int width, void (*b)(void *, int64_t), void *c) {
		const int want = width - 1;
		while ((int)workers.size() < want) {
			const int index = (int)workers.size();
			workers.emplace_back([this, index] { worker(index); });
		}
		{
			std::lock_guard<std::mutex> held(lock);
			body = b;
			context = c;
			chunks = n;
			helpers = want;
			checked_out = 0;
			next.store(0, std::memory_order_relaxed);
			done.store(0, std::memory_order_relaxed);
			generation += 1;
		}
		wake.notify_all();
		work(b, c, n);
		int spins = 0;
		for (;;) {
			{
				std::unique_lock<std::mutex> held(lock);
				if (done.load(std::memory_order_acquire) == n && checked_out == want) {
					return;
				}
				if (spins >= SPINS) {
					finished.wait(held, [&] { return done.load(std::memory_order_acquire) == n && checked_out == want; });
					return;
				}
			}
			spins += 1;
			std::this_thread::yield();
		}
	}

	void stop() {
		{
			std::lock_guard<std::mutex> held(lock);
			stopping = true;
		}
		wake.notify_all();
		for (std::thread &t : workers) {
			t.join();
		}
		workers.clear();
	}
};

// Made on the first wide loop, ended by `shutdown` (never destroyed by itself: a thread still
// joinable at the process's end would abort it).
Pool *pool = nullptr;

} // namespace

bool available() { return true; }

int default_width() {
	const int cores = (int)std::thread::hardware_concurrency();
	const int width = cores - 1;
	return width < 1 ? 1 : (width > MAX_WIDTH ? MAX_WIDTH : width);
}

void run(int64_t chunks, int width, void (*body)(void *, int64_t), void *context) {
	width = width > MAX_WIDTH ? MAX_WIDTH : width;
	if (width > chunks) {
		width = (int)chunks;
	}
	if (width <= 1) {
		run_here(chunks, body, context);
		return;
	}
	if (pool == nullptr) {
		pool = new Pool();
	}
	bool idle = false;
	if (!pool->busy.compare_exchange_strong(idle, true)) {
		run_here(chunks, body, context);
		return;
	}
	pool->run(chunks, width, body, context);
	pool->busy.store(false);
}

void shutdown() {
	if (pool != nullptr) {
		pool->stop();
		delete pool;
		pool = nullptr;
	}
}

#else

bool available() { return false; }

int default_width() { return 1; }

void run(int64_t chunks, int width, void (*body)(void *, int64_t), void *context) {
	(void)width;
	run_here(chunks, body, context);
}

void shutdown() {}

#endif

} // namespace jobs
