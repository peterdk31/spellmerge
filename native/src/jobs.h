// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Jobs: running one loop on several threads (shot scale H5, docs/milestones/shot-scale.md).
//
// A kernel hands `for_spans` the length of a loop and a body for one span of it; the spans run on
// up to `width` threads, this one among them, and `for_spans` returns once every span is done.
// Nothing here knows what a loop computes, and no kernel knows a thread: this file and jobs.cpp
// are the only native code that does (ci/smbot/rules.py, NATIVE_THREADS_FILE).
//
// A result never depends on the threads (rule T2): a loop is cut into spans of a fixed size,
// whatever the width; each span writes only what is its own (its slots, its row of a table), so
// which thread runs it, and when, changes nothing; and whatever spans share is combined after,
// in span order, by the caller. One thread or sixteen, the bits are the same, and
// tests/core/test_native_kernel.gd checks it.
//
// A body runs on a worker thread: it computes on plain memory only, calls no engine API that
// is not a pure function (no Variant of a packed array or an Object, no printing, no ERR_ macros),
// and runs no `for_spans` of its own (one nested would run on the calling thread alone).
//
// A build without threads (the web's, `threads=no`) runs every span on the calling thread.

#pragma once

#include <cstdint>

namespace jobs {

// The most threads one loop runs on.
constexpr int MAX_WIDTH = 16;

// Whether this build can run a loop on more than one thread.
bool available();
// The width a kernel takes unless told another: the machine's cores, less one for the engine, at
// least 1 and at most MAX_WIDTH; 1 without threads.
int default_width();
// Runs body(context, chunk) for every chunk in [0, chunks), on up to `width` threads (the caller's
// among them), and returns once all are done.
void run(int64_t chunks, int width, void (*body)(void *, int64_t), void *context);
// At the module's end: the workers stop and are joined.
void shutdown();

// The number of spans of `span` that cover `count`.
constexpr int64_t spans_of(int64_t count, int64_t span) { return count <= 0 ? 0 : (count + span - 1) / span; }

// `f(index, begin, end)` for each span [begin, end) of `span` items covering [0, count), on up to
// `width` threads. `index` is the span's number (0 first), for a table of what each span found.
template <typename F>
void for_spans(int64_t count, int64_t span, int width, F &&f) {
	struct Context {
		F *f;
		int64_t count;
		int64_t span;
	};
	Context context{ &f, count, span };
	run(spans_of(count, span), width, [](void *c, int64_t index) {
		const Context &x = *static_cast<Context *>(c);
		const int64_t begin = index * x.span;
		const int64_t end = begin + x.span < x.count ? begin + x.span : x.count;
		(*x.f)(index, begin, end);
	}, &context);
}

} // namespace jobs
