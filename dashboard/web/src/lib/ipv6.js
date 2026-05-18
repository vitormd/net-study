// Decodificação estrutural de endereços IPv6 — lógica pura, sem Vue.

// Expande um endereço IPv6 para 8 hextets completos (4 hex digits cada).
export function expandIPv6(addr) {
  addr = addr.replace(/%.*/, '') // remove scope id (%eth0)
  if (!addr.includes(':')) return null
  const [head, tail] = addr.split('::')
  const left = head ? head.split(':') : []
  const right = tail !== undefined ? tail.split(':') : []
  const missing = 8 - left.length - right.length
  if (missing < 0) return null
  const full = [...left, ...Array(missing).fill('0'), ...right]
  if (full.length !== 8) return null
  return full.map((h) => h.padStart(4, '0').toLowerCase())
}

export function classifyIPv6(hextets) {
  const first = parseInt(hextets[0], 16)
  if (hextets.every((h, i) => (i < 7 ? h === '0000' : h === '0001'))) return 'loopback'
  if ((first & 0xffc0) === 0xfe80) return 'linklocal'
  if ((first & 0xfe00) === 0xfc00) return 'ula'
  if ((first & 0xff00) === 0xff00) return 'multicast'
  if (hextets[0] === '2001' && hextets[1] === '0db8') return 'documentation'
  if ((first & 0xe000) === 0x2000) return 'global'
  return 'unknown'
}

const PARTS_BY_KIND = {
  global: [
    { cls: 'prefix', name: 'global unicast prefix (3 bits 2000::/3 ↦ alocado pela IANA)', range: [0, 0], hint: 'fixa o tipo: 001x' },
    { cls: 'global', name: 'global routing prefix (até /48, RIR + ISP + você)', range: [0, 2], hint: 'rotável pela internet' },
    { cls: 'subnet', name: 'subnet ID (16 bits, 1 a 65k sub-redes)', range: [3, 3], hint: 'sua organização escolhe' },
    { cls: 'interface', name: 'interface identifier (64 bits)', range: [4, 7], hint: 'EUI-64, SLAAC privacidade, ou manual' }
  ],
  ula: [
    { cls: 'prefix', name: 'ULA prefix (fc00::/7)', range: [0, 0], hint: 'rede privada, não roteável fora do site' },
    { cls: 'global', name: 'global ID (40 bits — deveria ser aleatório)', range: [0, 2], hint: 'evita colisão se redes se unirem' },
    { cls: 'subnet', name: 'subnet ID (16 bits)', range: [3, 3], hint: 'até 65k VLANs/sub-redes' },
    { cls: 'interface', name: 'interface identifier (64 bits)', range: [4, 7], hint: 'identifica a interface dentro da subnet' }
  ],
  linklocal: [
    { cls: 'prefix', name: 'link-local prefix (fe80::/10)', range: [0, 0], hint: 'só vale dentro do link físico — não atravessa roteador' },
    { cls: 'global', name: 'zeros (54 bits reservados)', range: [0, 3], hint: 'sempre 0 nesse formato' },
    { cls: 'interface', name: 'interface identifier (64 bits)', range: [4, 7], hint: 'auto-configurado a partir do MAC ou aleatório' }
  ],
  loopback: [
    { cls: 'prefix', name: 'loopback ::1', range: [0, 7], hint: 'equivalente ao 127.0.0.1' }
  ],
  documentation: [
    { cls: 'prefix', name: 'documentation prefix 2001:db8::/32', range: [0, 1], hint: 'reservado para exemplos (RFC 3849)' },
    { cls: 'subnet', name: 'subnet ID', range: [2, 3], hint: 'arbitrário (só pra exemplos)' },
    { cls: 'interface', name: 'interface identifier', range: [4, 7], hint: 'arbitrário' }
  ],
  multicast: [
    { cls: 'prefix', name: 'multicast prefix (ff00::/8)', range: [0, 0], hint: 'um-para-muitos; substitui o broadcast IPv4' },
    { cls: 'global', name: 'flags + scope', range: [0, 0], hint: 'os 8 bits seguintes definem escopo (link/site/global)' },
    { cls: 'interface', name: 'group ID', range: [1, 7], hint: 'identifica o grupo multicast' }
  ],
  unknown: [
    { cls: 'prefix', name: 'endereço fora dos blocos conhecidos', range: [0, 7], hint: '' }
  ]
}

const DESCRIPTIONS = {
  global: 'Endereço IPv6 global unicast — único na internet inteira. Funciona da mesma forma que um IPv4 público, mas com prefixos hierárquicos: IANA → RIR (LACNIC/ARIN/RIPE/APNIC/AfriNIC) → ISP → você → interfaces.',
  ula: 'Unique Local Address — equivalente IPv6 dos endereços privados (10.x, 192.168.x). Roteável dentro da sua infra, não na internet pública. O lab usa fd00:dead:beef::/64.',
  linklocal: 'Link-local — válido só dentro do mesmo link físico (mesma LAN). Cada interface IPv6 tem um automaticamente. Não passa por roteador.',
  documentation: '2001:db8::/32 — reservado pela RFC 3849 apenas para documentação e exemplos. Nunca usar em produção.',
  loopback: '::1 — loopback, o equivalente IPv6 de 127.0.0.1.',
  multicast: 'Multicast — pacote enviado a um grupo. IPv6 não tem broadcast; usa multicast com escopos (link, site, organização, global).',
  unknown: 'Endereço fora dos blocos comuns. Pode ser reservado, experimental ou simplesmente inválido.'
}

// Decodifica um endereço. Retorna { ok, ... } pro componente renderizar.
export function decodeIPv6(addr) {
  const hextets = expandIPv6(addr)
  if (!hextets) return { ok: false, input: addr }

  const kind = classifyIPv6(hextets)
  const parts = PARTS_BY_KIND[kind]

  // Cada hextet recebe a classe da fatia que o cobre.
  const segments = hextets.map((h, i) => {
    const seg = parts.find((p) => i >= p.range[0] && i <= p.range[1])
    return { hex: h, cls: seg ? seg.cls : 'zero' }
  })

  const fields = parts.map((p) => ({
    cls: p.cls,
    name: p.name,
    hint: p.hint,
    slice: hextets.slice(p.range[0], p.range[1] + 1).join(':')
  }))

  return {
    ok: true,
    kind,
    expanded: hextets.join(':'),
    description: DESCRIPTIONS[kind],
    segments,
    fields
  }
}
