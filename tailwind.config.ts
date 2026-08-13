import type { Config } from 'tailwindcss'
export default { content: ['./app/**/*.{js,ts,jsx,tsx,mdx}','./components/**/*.{js,ts,jsx,tsx,mdx}'], theme: { extend: { colors: { cande: { 50:'#fff5f7',100:'#ffe4ea',200:'#ffc9d5',500:'#f22e62',600:'#dc1f50',700:'#b91742',900:'#611126' } }, boxShadow: { soft:'0 12px 35px rgba(130, 21, 55, .10)' } } }, plugins: [] } satisfies Config
