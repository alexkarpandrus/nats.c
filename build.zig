const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_libsodium = b.option(bool, "enable-libsodium", "Build with libsodium for higher-performance signing (default: true)") orelse true;
    const enable_tls = b.option(bool, "enable-tls", "Build TLS support (default: true)") orelse true;
    const tls_verify = b.option(bool, "force-host-verify", "Force hostname verification for TLS connections (default: true)") orelse true;
    const enable_streaming = b.option(bool, "enable-streaming", "Build with streaming support (default: true)") orelse true;
    const enable_pic = b.option(bool, "enable-pic", "Enable Position Independent Code for shared libraries") orelse false;

    const upstream = b.dependency("nats_c", .{});
    const tls_dep = if (enable_tls) b.lazyDependency(
        "libressl",
        .{ .target = target, .optimize = optimize },
    ) else null;
    const protobuf_runtime = if (enable_streaming) b.lazyDependency(
        "protobuf_c",
        .{ .target = target, .optimize = optimize },
    ) else null;
    const libsodium_dep = if (enable_libsodium) b.lazyDependency(
        "libsodium",
        .{
            .target = target,
            .optimize = optimize,
            .static = true,
            .shared = false,
        },
    ) else null;

    const lib = b.addStaticLibrary(.{
        .name = "nats",
        .target = target,
        .optimize = optimize,
        .pic = enable_pic,
    });

    const cflags: []const []const u8 = &.{};

    const src_root = upstream.path("src");

    lib.linkLibC();
    lib.addCSourceFiles(.{
        .root = src_root,
        .files = common_sources,
        .flags = cflags,
    });
    lib.addIncludePath(upstream.path("include"));

    const tinfo = target.result;
    switch (tinfo.os.tag) {
        .windows => {
            lib.addCSourceFiles(.{
                .root = src_root,
                .files = win_sources,
                .flags = cflags,
            });
            lib.linkSystemLibrary("ws2_32");
        },
        else => if (tinfo.os.tag.isDarwin()) {
            lib.root_module.addCMacro("DARWIN", "");
            lib.addCSourceFiles(.{
                .root = src_root,
                .files = unix_sources,
                .flags = cflags,
            });
        } else {
            lib.root_module.addCMacro("_GNU_SOURCE", "");
            lib.root_module.addCMacro("LINUX", "");
            lib.addCSourceFiles(.{
                .root = src_root,
                .files = unix_sources,
                .flags = if (enable_pic) &.{"-fPIC"} else &.{},
            });
            // just following the cmake logic
            if (!tinfo.abi.isAndroid()) {
                lib.linkSystemLibrary("pthread");
                lib.linkSystemLibrary("rt");
            }
        },
    }

    lib.root_module.addCMacro("_REENTRANT", "");

    for (install_headers) |header| {
        lib.installHeader(
            upstream.path(b.pathJoin(&.{ "src", header })),
            b.pathJoin(&.{ "nats", header }),
        );
    }

    if (tls_dep) |dep| {
        lib.root_module.addCMacro("NATS_HAS_TLS", "");
        lib.root_module.addCMacro("NATS_USE_OPENSSL_1_1", "");
        if (tls_verify)
            lib.root_module.addCMacro("NATS_FORCE_HOST_VERIFICATION", "");
        lib.linkLibrary(dep.artifact("ssl"));
    }

    if (protobuf_runtime) |dep| {
        lib.addIncludePath(upstream.path("deps"));
        lib.addIncludePath(upstream.path("stan"));
        lib.root_module.addCMacro("NATS_HAS_STREAMING", "");

        lib.addCSourceFiles(.{
            .root = src_root,
            .files = streaming_sources,
            .flags = cflags,
        });
        lib.linkLibrary(dep.artifact("protobuf_c"));
    }

    if (libsodium_dep) |dep| {
        lib.root_module.addCMacro("NATS_USE_LIBSODIUM", "");
        // yep
        lib.linkLibrary(dep.artifact(if (tinfo.isMinGW()) "libsodium-static" else "sodium"));
    }

    b.installArtifact(lib);
}

const install_headers: []const []const u8 = &.{
    "nats.h",
    "status.h",
    "version.h",
};

const common_sources: []const []const u8 = &.{
    "asynccb.c",
    "comsock.c",
    "crypto.c",
    "dispatch.c",
    "glib/glib.c",
    "glib/glib_async_cb.c",
    "glib/glib_dispatch_pool.c",
    "glib/glib_gc.c",
    "glib/glib_last_error.c",
    "glib/glib_ssl.c",
    "glib/glib_timer.c",
    "js.c",
    "kv.c",
    "nats.c",
    "nkeys.c",
    "opts.c",
    "pub.c",
    "stats.c",
    "sub.c",
    "url.c",
    "buf.c",
    "conn.c",
    "hash.c",
    "jsm.c",
    "msg.c",
    "natstime.c",
    "nuid.c",
    "parser.c",
    "srvpool.c",
    "status.c",
    "timer.c",
    "util.c",
};

const unix_sources: []const []const u8 = &.{
    "unix/cond.c",
    "unix/mutex.c",
    "unix/sock.c",
    "unix/thread.c",
};

const win_sources: []const []const u8 = &.{
    "win/cond.c",
    "win/mutex.c",
    "win/sock.c",
    "win/strings.c",
    "win/thread.c",
};

const streaming_sources: []const []const u8 = &.{
    "stan/conn.c",
    "stan/copts.c",
    "stan/msg.c",
    "stan/protocol.pb-c.c",
    "stan/pub.c",
    "stan/sopts.c",
    "stan/sub.c",
};
