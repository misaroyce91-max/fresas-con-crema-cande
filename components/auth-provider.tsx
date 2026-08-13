'use client'
import {createContext,useCallback,useContext,useEffect,useMemo,useState} from 'react'
import type {User} from '@supabase/supabase-js'
import {supabase} from '@/lib/supabase'

export type CustomerProfile={id:string;name:string;phone:string;points_balance:number;lifetime_points:number;created_at:string;customer_levels:{name:string;min_lifetime_points:number}|null}
type AuthValue={user:User|null;profile:CustomerProfile|null;loading:boolean;refreshProfile:()=>Promise<void>;signOut:()=>Promise<void>}
const AuthContext=createContext<AuthValue|null>(null)

export function normalizeMexicanPhone(value:string){const digits=value.replace(/\D/g,'');if(digits.length===10)return`+52${digits}`;if(digits.length===12&&digits.startsWith('52'))return`+${digits}`;if(digits.length===13&&digits.startsWith('521'))return`+52${digits.slice(3)}`;return value.startsWith('+')?value:`+${digits}`}

export function AuthProvider({children}:{children:React.ReactNode}){
 const[user,setUser]=useState<User|null>(null),[profile,setProfile]=useState<CustomerProfile|null>(null),[loading,setLoading]=useState(true)
 const refreshProfile=useCallback(async()=>{if(!supabase)return;const{data:auth}=await supabase.auth.getUser();const next=auth.user??null;setUser(next);if(!next){setProfile(null);return}const{data}=await supabase.from('customers').select('id,name,phone,points_balance,lifetime_points,created_at,customer_levels(name,min_lifetime_points)').eq('id',next.id).single();setProfile(data as unknown as CustomerProfile|null)},[])
 useEffect(()=>{if(!supabase){setLoading(false);return}refreshProfile().finally(()=>setLoading(false));const{data}=supabase.auth.onAuthStateChange(()=>setTimeout(()=>refreshProfile(),0));return()=>data.subscription.unsubscribe()},[refreshProfile])
 const value=useMemo<AuthValue>(()=>({user,profile,loading,refreshProfile,signOut:async()=>{if(supabase)await supabase.auth.signOut();setUser(null);setProfile(null)}}),[loading,profile,refreshProfile,user])
 return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
export function useAuth(){const value=useContext(AuthContext);if(!value)throw new Error('useAuth fuera de AuthProvider');return value}
