'use client';
import {useEffect} from 'react';
export default function PWARegister(){useEffect(()=>{if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js',{updateViaCache:'none'}).then(r=>r.update()).catch(()=>{})},[]);return null}
