import QRCode from 'qrcode'
const CLIENT_URL='https://fresas-con-crema-cande.vercel.app/'
export async function GET(){const png=await QRCode.toBuffer(CLIENT_URL,{type:'png',width:1600,margin:4,errorCorrectionLevel:'H',color:{dark:'#18181b',light:'#ffffff'}});return new Response(new Uint8Array(png),{headers:{'Content-Type':'image/png','Content-Disposition':'inline; filename="qr-fresas-cande.png"','Cache-Control':'public, max-age=31536000, immutable'}})}
