import './globals.css';
import './solar-theme.css';
import './workflow.css';
import PWARegister from './pwa-register';
export const metadata={title:'عبدالرحمن سولار',description:'إدارة فرع الطاقة الشمسية',manifest:'/manifest.webmanifest',themeColor:'#0b8f82',icons:{icon:'/icon.svg',apple:'/icon.svg'}};
export const viewport={width:'device-width',initialScale:1,viewportFit:'cover',themeColor:'#0b8f82'};
export default function Layout({children}){return <html lang="ar" dir="rtl"><body>{children}<PWARegister/></body></html>}
