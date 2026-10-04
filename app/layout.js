import './globals.css';
import './solar-theme.css';
import './workflow.css';
import './compact-theme.css';
import './warehouse.css';
import './tahseel.css';
import './data-reset.css';
import PWARegister from './pwa-register';
export const metadata={title:'عبدالرحمن سولار',description:'إدارة فرع الطاقة الشمسية',manifest:'/manifest.webmanifest',icons:{icon:'/icon.svg',apple:'/icon.svg'}};
export const viewport={width:'device-width',initialScale:1,viewportFit:'cover',themeColor:'#1c254b'};
export default function Layout({children}){return <html lang="ar" dir="rtl"><body>{children}<PWARegister/></body></html>}
