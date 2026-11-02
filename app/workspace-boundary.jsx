'use client';
import {Component} from 'react';
import AppIcon from './app-icons';
export default class WorkspaceBoundary extends Component{
 state={failed:false,section:this.props.section};
 static getDerivedStateFromError(){return {failed:true};}
 static getDerivedStateFromProps(props,state){return props.section!==state.section?{failed:false,section:props.section}:null;}
 componentDidCatch(error){console.error('Workspace rendering failed',error);}
 render(){return this.state.failed?<section className="workspaceFailure" role="alert"><AppIcon name="info" size={30}/><h2>تعذر عرض هذا القسم</h2><p>أعد فتح القسم، أو ارجع للرئيسية وتابع عملك.</p><div><button type="button" onClick={()=>this.setState({failed:false})}>إعادة فتح القسم</button><button type="button" onClick={this.props.onHome}>الرئيسية</button></div></section>:this.props.children;}
}
