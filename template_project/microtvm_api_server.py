# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

import fcntl
import multiprocessing
import atexit
import os
import signal
import shlex
import os.path
import pathlib
import select
import shutil
import logging
import subprocess
import tarfile
import tempfile
import time
import termios
import tty


def configure_pty_raw(fd):
    attrs = termios.tcgetattr(fd)
    attrs[3] &= ~(termios.ECHO | termios.ICANON | termios.ISIG | termios.IEXTEN)  # lflag
    attrs[1] &= ~termios.OPOST  # oflag
    attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.ICRNL | termios.INLCR)  # iflag
    attrs[2] |= termios.CS8  # cflag
    attrs[6][termios.VMIN] = 1
    attrs[6][termios.VTIME] = 0
    tty.setraw(fd)
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


import warnings

warnings.simplefilter("ignore", ResourceWarning)
warnings.simplefilter("ignore", DeprecationWarning)
warnings.filterwarnings("ignore", category=DeprecationWarning)
import distutils.util

from tvm.micro.project_api import server

_LOG = logging.getLogger(__name__)
_LOG.setLevel(logging.WARNING)

PRINT = False
# PRINT = True

PROJECT_DIR = pathlib.Path(os.path.dirname(__file__) or os.getcwd())


MODEL_LIBRARY_FORMAT_RELPATH = "model.tar"


IS_TEMPLATE = not os.path.exists(os.path.join(PROJECT_DIR, MODEL_LIBRARY_FORMAT_RELPATH))

# Used this size to pass most CRT tests in TVM.
# WORKSPACE_SIZE_BYTES = 4 * 1024 * 1024
WORKSPACE_SIZE_BYTES = 2 * 1024 * 1024
# WORKSPACE_SIZE_BYTES = 1 * 1024 * 1024

CPU_FREQ = 100e6

# ARCH = "rv32gc"
# ABI = "ilp32d"
# TRIPLE = "riscv64-unknown-elf"
NPROC = multiprocessing.cpu_count()


def str2bool(value, allow_none=False):
    if value is None:
        assert allow_none, "str2bool received None value while allow_none=False"
        return value
    return bool(value) if isinstance(value, (int, bool)) else bool(distutils.util.strtobool(value))


def check_call(cmd_args, *args, **kwargs):
    cwd_str = "" if "cwd" not in kwargs else f" (in cwd: {kwargs['cwd']})"
    _LOG.info("run%s: %s", cwd_str, " ".join(shlex.quote(a) for a in cmd_args))
    return subprocess.check_call(cmd_args, *args, **kwargs)


class Handler(server.ProjectAPIHandler):

    def __init__(self):
        super(Handler, self).__init__()
        self._proc = None
        self._pty_fd = None

    def server_info_query(self, tvm_version):
        return server.ServerInfo(
            platform_name="host",
            is_template=IS_TEMPLATE,
            model_library_format_path="" if IS_TEMPLATE else PROJECT_DIR / MODEL_LIBRARY_FORMAT_RELPATH,
            project_options=[
                server.ProjectOption(
                    "verbose",
                    optional=["build", "flash"],
                    type="bool",
                    default=False,
                    help="Run make with verbose output",
                ),
                server.ProjectOption(
                    "quiet",
                    optional=["build", "flash"],
                    type="bool",
                    default=True,
                    help="Supress all compilation messages",
                ),
                server.ProjectOption(
                    "debug",
                    optional=["generate_project", "build"],
                    type="bool",
                    default=False,
                    help="Build with debugging symbols and -O0",
                ),
                server.ProjectOption(
                    "workspace_size_bytes",
                    optional=["generate_project"],
                    type="int",
                    default=WORKSPACE_SIZE_BYTES,
                    help="Sets the value of TVM_WORKSPACE_SIZE_BYTES.",
                ),
                server.ProjectOption(
                    "verilog_file",
                    optional=["generate_project"],
                    type="str",
                    default=None,
                    help="Path to custom cfu.v file.",
                ),
                # server.ProjectOption(
                #     "arch",
                #     optional=["build"],
                #     default=ARCH,
                #     type="str",
                #     help="Name used ARCH.",
                # ),
                # server.ProjectOption(
                #     "abi",
                #     optional=["build"],
                #     default=ABI,
                #     type="str",
                #     help="Name used ABI.",
                # ),
                server.ProjectOption(
                    "gcc_prefix",
                    optional=["build"],
                    default="",
                    type="str",
                    help="Path to COMPILER.",
                ),
                # server.ProjectOption(
                #     "gcc_name",
                #     optional=["build"],
                #     default=TRIPLE,
                #     type="str",
                #     help="Name of COMPILER.",
                # ),
                server.ProjectOption(
                    "cfu_root",
                    required=["open_transport", "build", "flash"],
                    type="str",
                    help="Path to cfu_playground repository.",
                ),
                server.ProjectOption(
                    "verilator_install_dir",
                    required=["flash"],
                    type="str",
                    help="Path to verilator installation.",
                ),
            ],
        )

    # These files and directories will be recursively copied into generated projects from the CRT.
    CRT_COPY_ITEMS = ("src", "include")

    def _populate_makefile(
        self,
        makefile_template_path: pathlib.Path,
        makefile_path: pathlib.Path,
        memory_size: int,
        debug: bool,
    ):
        """Generate Makefile file from template."""

        with open(makefile_path, "w") as makefile_f:
            with open(makefile_template_path, "r") as makefile_template_f:
                for line in makefile_template_f:
                    makefile_f.write(line)
                    if "Extra options" in line:
                        if not debug:
                            makefile_f.write("DEFINES += NDEBUG\n")
                        makefile_f.write(f"DEFINES += TVM_WORKSPACE_SIZE_BYTES={memory_size}\n")

    def generate_project(self, model_library_format_path, standalone_crt_dir, project_dir, options):
        # Make project directory.
        project_dir.mkdir(parents=True)
        current_dir = pathlib.Path(__file__).parent.absolute()

        # Copy ourselves to the generated project. TVM may perform further build steps on the generated project
        # by launching the copy.
        shutil.copy2(__file__, project_dir / os.path.basename(__file__))

        # Place Model Library Format tarball in the special location, which this script uses to decide
        # whether it's being invoked in a template or generated project.
        project_model_library_format_path = project_dir / MODEL_LIBRARY_FORMAT_RELPATH
        shutil.copy2(model_library_format_path, project_model_library_format_path)

        # Extract Model Library Format tarball.into <project_dir>/model.
        extract_path = project_dir / project_model_library_format_path.stem
        with tarfile.TarFile(project_model_library_format_path) as tf:
            os.makedirs(extract_path)
            tf.extractall(path=extract_path)

        # Populate Makefile
        self._populate_makefile(
            current_dir / f"Makefile.template",
            project_dir / "Makefile",
            options.get("workspace_size_bytes", WORKSPACE_SIZE_BYTES),
            options.get("debug", False),
        )
        # Copy project files
        verilog_file = options.get("verilog_file")
        if verilog_file is None:
            verilog_file = current_dir / "cfu.v"
        else:
            verilog_file = Path(verilog_file)
        assert verilog_file.is_file(), f"Missing file: {verilog_file}"
        shutil.copy2(
            verilog_file,
            project_dir / "cfu.v",
        )
        proj_name = project_dir.name
        shutil.copy2(
            current_dir / "cfu.robot",
            project_dir / f"{proj_name}.robot",
        )

        # Populate src/
        src_dir = project_dir / "src"
        src_dir.mkdir()
        shutil.copy2(
            current_dir / "src" / "proj_menu.cc",
            src_dir / "proj_menu.cc",
        )
        shutil.copy2(
            current_dir / "src" / "platform.cc",
            src_dir / "platform.cc",
        )

        # Populate crt_config.h
        crt_config_dir = project_dir / "src"
        shutil.copy2(
            current_dir / "crt_config" / "crt_config.h",
            crt_config_dir / "crt_config.h",
        )

        # Populate CRT.
        # crt_path = project_dir / "crt"
        crt_path = src_dir / "runtime"
        os.mkdir(crt_path)
        for item in self.CRT_COPY_ITEMS:
            src_path = standalone_crt_dir / item
            dst_path = crt_path / item
            if os.path.isdir(src_path):
                shutil.copytree(src_path, dst_path)
            else:
                shutil.copy2(src_path, dst_path)

        support_path = src_dir / "support"
        shutil.copytree(current_dir / "support", support_path, dirs_exist_ok=True)

        # Copy codegen files to src
        shutil.copytree(extract_path / "codegen", src_dir / "codegen")
        # Copy runtime files to src
        # shutil.copytree(extract_path / "runtime", src_dir / "runtime")

    def prepare_environment(self, env: dict, options):
        new_path = env.get("PATH", "")
        gcc_prefix = options.get("gcc_prefix", None)
        if gcc_prefix is not None:
            new_path = f"{gcc_prefix}/bin:{new_path}"
        verilator_install_dir = options.get("verilator_install_dir", None)
        if verilator_install_dir is not None:
            new_path = f"{verilator_install_dir}/bin:{new_path}"
        env["PATH"] = new_path
        return env

    def get_cfu_make_args(self, options):
        ret = []
        verbose = options.get("verbose", None)
        if verbose is not None:
            ret.append(f"VERBOSE=1")
            ret.append(f"V=1")
        cfu_root = options.get("cfu_root", None)
        if cfu_root is None:
            assert "CFU_ROOT" in os.environ
        if cfu_root is not None:
            ret.append(f"CFU_ROOT={cfu_root}")
        proj_name = PROJECT_DIR.name
        ret.append(f"PROJ={proj_name}")
        ret.append(f"PROJ_DIR={PROJECT_DIR}")
        return ret

    def build(self, options):
        if PRINT:
            print("build")
        env = self.prepare_environment(os.environ.copy(), options)
        make_args = []
        make_args += self.get_cfu_make_args(options)
        # print("make_args", make_args)
        if str2bool(options.get("quiet"), True):
            check_call(
                ["make", "software", *make_args], cwd=PROJECT_DIR, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL
            )
        else:
            check_call(["make", "software", *make_args], cwd=PROJECT_DIR)

    def flash(self, options):
        # used for building the verilator model
        if PRINT:
            print("flash")
        env = self.prepare_environment(os.environ.copy(), options)
        make_args = []
        make_args += self.get_cfu_make_args(options)
        # print("make_args", make_args)
        if str2bool(options.get("quiet"), True):
            check_call(
                ["make", "renode-scripts", *make_args],
                cwd=PROJECT_DIR,
                stderr=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
            )
        else:
            check_call(["make", "renode-scripts", *make_args], cwd=PROJECT_DIR)

    def _set_nonblock(self, fd):
        flag = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, flag | os.O_NONBLOCK)
        new_flag = fcntl.fcntl(fd, fcntl.F_GETFL)
        assert (new_flag & os.O_NONBLOCK) != 0, "Cannot set file descriptor {fd} to non-blocking"

    def open_transport(self, options):
        if PRINT:
            print("open_transport")
        cfu_root = options.get("cfu_root", None)
        if cfu_root is None:
            cfu_root = os.environ.get("CFU_ROOT")
        assert cfu_root is not None
        cfu_root = pathlib.Path(cfu_root)
        assert cfu_root.is_dir(), f"Missing: {cfu_root}"
        renode_exe = cfu_root / "third_party" / "renode" / "renode"
        assert renode_exe.is_file(), f"Missing: {renode_exe}"
        build_dir = PROJECT_DIR / "build"
        assert build_dir.is_dir(), f"Missing: {build_dir}"
        sim_dir = build_dir / "renode"
        assert sim_dir.is_dir(), f"Missing: {sim_dir}"
        pty_path = PROJECT_DIR / "uart.pty"
        if pty_path.exists():
            os.unlink(pty_path)
        renode_args = []
        renode_args.append(renode_exe)
        renode_args += ["-e", "s @digilent_arty.resc"]
        renode_args += ["-e", f'emulation CreateUartPtyTerminal "term" "{pty_path}"']
        renode_args += ["-e", "connector Connect sysbus.uart term"]
        # renode_args += ["-e", "sysbus.uart WriteChar 0x33"]  # write 3 char for project menu
        # print("renode_args", renode_args)
        # print("sim_dir", sim_dir)
        # input(">")
        self._proc = subprocess.Popen(
            renode_args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            # stderr=subprocess.PIPE,
            bufsize=0,
            preexec_fn=os.setsid,
            cwd=sim_dir,
        )
        # print("A")
        # Wait for PTY to appear
        deadline = time.time() + 30.0
        while not os.path.exists(pty_path):
            if time.time() > deadline:
                raise RuntimeError(f"PTY not created: {pty_path}")
            time.sleep(0.05)

        # Open PTY
        self._pty_fd = os.open(pty_path, os.O_RDWR | os.O_NOCTTY)

        # Put PTY into raw mode (CRITICAL)
        attrs = termios.tcgetattr(self._pty_fd)
        tty.setraw(self._pty_fd)
        termios.tcsetattr(self._pty_fd, termios.TCSANOW, attrs)
        configure_pty_raw(self._pty_fd)

        # Non-blocking
        self._set_nonblock(self._pty_fd)
        # input("press enter to cont")
        # print("goooo")
        self._await_ready([], [self._pty_fd])
        os.write(self._pty_fd, b"3")
        # self._await_ready([self._pty_fd], [])
        # os.read(self._pty_fd, 24)
        self._drain_until_rpc_start()
        # input(">>>>>>>")
        # time.sleep(30.0)
        # print("abc?")

        atexit.register(lambda: self.close_transport())
        return server.TransportTimeouts(
            session_start_retry_timeout_sec=0,
            session_start_timeout_sec=0,
            session_established_timeout_sec=0,
            # session_start_retry_timeout_sec=15.0,
            # session_start_timeout_sec=15.0,
            # session_established_timeout_sec=15.0,
        )

    def close_transport(self):
        if PRINT:
            print("close_transport")
        if self._pty_fd is not None:
            try:
                os.close(self._pty_fd)
            except OSError:
                pass
            self._pty_fd = None
        if self._proc is not None:
            proc = self._proc
            pgrp = os.getpgid(proc.pid)
            self._proc = None
            proc.terminate()
            proc.kill()
            proc.wait()
            # os.killpg(pgrp, signal.SIGKILL)
        pty_path = PROJECT_DIR / "uart.pty"
        if pty_path.exists():
            os.unlink(pty_path)

    def _await_ready(self, rlist, wlist, timeout_sec=None, end_time=None):
        # print("await_ready", rlist, wlist, timeout_sec, end_time)
        if timeout_sec is None and end_time is not None:
            timeout_sec = max(0, end_time - time.monotonic())

        # print("abc")
        rlist, wlist, xlist = select.select(rlist, wlist, rlist + wlist, timeout_sec)
        # print("def")
        if not rlist and not wlist and not xlist:
            raise server.IoTimeoutError()

        return True

    def _drain_until_rpc_start(self, timeout=10.0):
        if PRINT:
            print("_drain_until_rpc_start")
        end = time.time() + timeout
        hist = b""
        while time.time() < end:
            r, _, _ = select.select([self._pty_fd], [], [], 0.05)
            if not r:
                continue

            b = os.read(self._pty_fd, 1)
            hist += b
            if not b:
                # print("empty read")
                continue

            if b == b"\xfe":
                # push back into buffer
                # print("found start byte", b)
                self._rx_buffer = b
                # print("hist", hist)
                return
            # print("received non-start byte", b)

        # print("hist", hist)
        raise RuntimeError("RPC start byte not found")

    def read_transport(self, n, timeout_sec):
        if PRINT:
            print("read_transport", n)
        if self._rx_buffer:
            # print("fill start byte")
            data = self._rx_buffer
            self._rx_buffer = b""
            if PRINT:
                print("ret", data)
            return data
        if self._proc is None:
            raise server.TransportClosedError()
        assert self._pty_fd is not None

        end_time = None if timeout_sec is None else time.monotonic() + timeout_sec

        try:
            self._await_ready([self._pty_fd], [], end_time=end_time)
            # print("read?")
            to_return = os.read(self._pty_fd, n)
            # print("ok!")
        except BrokenPipeError:
            to_return = 0

        if not to_return:
            self.close_transport()
            raise server.TransportClosedError()
        if PRINT:
            print("ret", to_return)

        return to_return

    def write_transport(self, data, timeout_sec):
        if PRINT:
            print("write_transport", data)
        if self._proc is None:
            raise server.TransportClosedError()

        assert self._pty_fd is not None
        end_time = None if timeout_sec is None else time.monotonic() + timeout_sec

        data_len = len(data)
        while data:
            time.sleep(0.05)
            self._await_ready([], [self._pty_fd], end_time=end_time)
            try:
                num_written = os.write(self._pty_fd, data)
            except BrokenPipeError:
                num_written = 0

            if not num_written:
                self.disconnect_transport()
                raise server.TransportClosedError()

            data = data[num_written:]


if __name__ == "__main__":
    server.main(Handler())
