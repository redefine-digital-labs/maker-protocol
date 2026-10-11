/// Frozen visual values. Hashes commit to these values; they do not certify pixels.
/// Coordinates are milli-pixels, scale/opacity/gradient positions are ppm.
/// The 17 blend codes retain the existing Maker renderer menu order.
module soulidity_visual::visual;

use std::bcs;
use std::hash;

const EInvalid:u64=1; const EBounds:u64=2; const EDuplicate:u64=3;
const EReference:u64=4; const ERule:u64=5; const EColor:u64=6;
const MAX_PIXELS:u64=8388608;
const MAX_FRAGMENTS:u64=500;

public struct Signed has copy,drop,store {negative:bool,magnitude:u64}
public struct Transform has copy,drop,store {x:Signed,y:Signed,scale_ppm:u64,rotation:Signed}
public struct Track has copy,drop,store {key:vector<u8>,order:u64,locked:bool}
public struct Stop has copy,drop,store {offset_ppm:u64,rgba:u32}
public struct Swatch has copy,drop,store {key:vector<u8>,rgba:u32,stops:vector<Stop>}
public struct Channel has copy,drop,store {key:vector<u8>,default:vector<u8>,editable:bool,swatches:vector<Swatch>}
public struct ColorChoice has copy,drop,store {channel:vector<u8>,swatch:Option<vector<u8>>}
/// None product/version selects a semantic path in this Scene. Some pins both.
public struct Selector has copy,drop,store {product:Option<ID>,version:Option<u64>,part:vector<u8>,item:Option<vector<u8>>,style:Option<vector<u8>>}
public struct Fact has copy,drop,store {product:ID,version:u64,part:vector<u8>,item:vector<u8>,style:vector<u8>}
/// Postfix SELECTED=0, NOT=1, ALL=2, ANY=3; empty means unconditional.
public struct Token has copy,drop,store {opcode:u8,selector:Option<Selector>,arity:u16}
public struct Rule has copy,drop,store {key:vector<u8>,kind:u8,trigger:Selector,any:bool,targets:vector<Selector>}
/// Conditional anchor variants are resolved from actual final selected Sources.
public struct AnchorVariant has drop {key:vector<u8>,when:vector<Token>}
public struct Anchor has copy,drop,store {key:vector<u8>,when:vector<Token>,x:Signed,y:Signed}
public struct Scene has copy,drop,store {
    domain:vector<u8>,schema:u16,width:u64,height:u64,origin_x:Signed,origin_y:Signed,
    axes:u8,sampling:u8,clip_viewport:bool,color_space:u8,premultiplied:bool,
    renderer:vector<u8>,body:vector<u8>,pose:vector<u8>,parts:vector<vector<u8>>,
    tracks:vector<Track>,channels:vector<Channel>,anchors:vector<Anchor>,rules:vector<Rule>,
}
/// Source crop plus authored placement preserves trim/padding and local pivot.
/// mask is a prior fragment index in this same Representation; no mask cycles.
public struct Fragment has copy,drop,store {
    key:vector<u8>,asset:vector<u8>,media:vector<u8>,byte_length:u64,
    image_width:u64,image_height:u64,crop_x:u64,crop_y:u64,crop_width:u64,crop_height:u64,
    local_x:u64,local_y:u64,track:vector<u8>,display_order:u64,anchor:vector<u8>,
    transform:Transform,opacity_ppm:u64,blend:u8,channel:Option<vector<u8>>,
    swatch:Option<vector<u8>>,mask:Option<u64>,visible:vector<Token>,
}
public struct Representation has copy,drop,store {
    domain:vector<u8>,schema:u16,scene_hash:vector<u8>,renderer:vector<u8>,
    canvas_width:u64,canvas_height:u64,fragments:vector<Fragment>,visible:vector<Token>,
}
public struct FragmentMap has copy,drop,store {index:u64,track:vector<u8>,anchor:vector<u8>,transform:Transform,channel:Option<vector<u8>>,swatch:Option<vector<u8>>}
public struct Mapping has copy,drop,store {representation:vector<u8>,scene:vector<u8>,maps:vector<FragmentMap>}
/// Standard render instructions preserve the source fragment, exact track,
/// palette/gradient, anchor and adapter transform. Clients execute these values.
public struct Layer has copy,drop,store {
    source:vector<u8>,part:vector<u8>,item:vector<u8>,style:vector<u8>,index:u64,
    track:Track,fragment:Fragment,anchor:Anchor,adapter:Option<Transform>,user:Transform,tint:vector<u8>,color:Option<Swatch>,
}

fun key(k:&vector<u8>){assert!(!k.is_empty() && k.length()<=64,EInvalid)}
fun digest(h:&vector<u8>){assert!(h.length()==32,EInvalid)}
public fun signed(negative:bool,magnitude:u64):Signed{assert!(magnitude<=8192000,EBounds);Signed{negative:negative && magnitude>0,magnitude}}
public fun transform(x:Signed,y:Signed,scale_ppm:u64,rotation:Signed):Transform{
    assert!(scale_ppm>0 && scale_ppm<=100000000 && rotation.magnitude<=360000,EBounds);Transform{x,y,scale_ppm,rotation}
}
public fun track(key:vector<u8>,order:u64,locked:bool):Track{key(&key);Track{key,order,locked}}
public fun stop(offset_ppm:u64,rgba:u32):Stop{assert!(offset_ppm<=1000000,EBounds);Stop{offset_ppm,rgba}}
public fun swatch(key:vector<u8>,rgba:u32,stops:vector<Stop>):Swatch{
    key(&key);assert!(stops.length()<=64,EBounds);let mut i=1;
    // Equal offsets preserve authored hard transitions and encounter order.
    while(i < stops.length()){assert!(stops[i-1].offset_ppm<=stops[i].offset_ppm,EColor);i=i+1};Swatch{key,rgba,stops}
}
public fun channel(key:vector<u8>,default:vector<u8>,editable:bool,swatches:vector<Swatch>):Channel{
    key(&key);key(&default);assert!(!swatches.is_empty() && swatches.length()<=256,EBounds);
    let mut seen=vector[];swatches.do_ref!(|s|{assert!(!seen.contains(&s.key),EDuplicate);seen.push_back(s.key)});
    assert!(seen.contains(&default),EColor);Channel{key,default,editable,swatches}
}
public fun color_choice(channel:vector<u8>,swatch:vector<u8>):ColorChoice{key(&channel);key(&swatch);ColorChoice{channel,swatch:option::some(swatch)}}
public fun selector(product:Option<ID>,version:Option<u64>,part:vector<u8>,item:Option<vector<u8>>,style:Option<vector<u8>>):Selector{
    key(&part);assert!(product.is_some()==version.is_some() && (style.is_none() || item.is_some()),EInvalid);
    if(product.is_some())assert!(*product.borrow()!=object::id_from_address(@0x0) && *version.borrow()>0,EInvalid);
    item.do_ref!(|v|key(v));style.do_ref!(|v|key(v));Selector{product,version,part,item,style}
}
public fun fact(product:ID,version:u64,part:vector<u8>,item:vector<u8>,style:vector<u8>):Fact{
    assert!(product!=object::id_from_address(@0x0) && version>0,EInvalid);key(&part);key(&item);key(&style);Fact{product,version,part,item,style}
}
public fun token(opcode:u8,selector:Option<Selector>,arity:u16):Token{
    assert!(opcode<=3,EInvalid);
    assert!(if(opcode==0)selector.is_some() && arity==0 else selector.is_none() && (if(opcode==1)arity==1 else arity>=2 && arity<=32),EInvalid);
    Token{opcode,selector,arity}
}
public fun validate_program(tokens:&vector<Token>){
    assert!(tokens.length()<=288,EBounds);if(tokens.is_empty())return;
    let mut depths=vector[];let mut leaves=0;
    tokens.do_ref!(|t|{
        if(t.opcode==0){leaves=leaves+1;assert!(leaves<=32,EBounds);depths.push_back(1u64)}
        else{let n=t.arity as u64;assert!(depths.length()>=n,ERule);let mut d=0;let mut i=0;
            while(i < n){let child=depths.pop_back();if(child>d)d=child;i=i+1};assert!(d < 8,EBounds);depths.push_back(d+1)}
    });assert!(depths.length()==1,ERule)
}
public fun selected(s:&Selector,facts:&vector<Fact>):bool{
    facts.any!(|f|f.part==s.part && (s.product.is_none() || (s.product==option::some(f.product) && s.version==option::some(f.version))) && (s.item.is_none() || s.item==option::some(f.item)) && (s.style.is_none() || s.style==option::some(f.style)))
}
public fun evaluate(tokens:&vector<Token>,facts:&vector<Fact>):bool{
    validate_program(tokens);if(tokens.is_empty())return true;let mut stack=vector[];
    tokens.do_ref!(|t|{if(t.opcode==0)stack.push_back(selected(t.selector.borrow(),facts))
        else if(t.opcode==1){let v=stack.pop_back();stack.push_back(!v)}
        else{let mut v=t.opcode==2;let mut i=0;while(i < (t.arity as u64)){let next=stack.pop_back();v=if(t.opcode==2)v && next else v || next;i=i+1};stack.push_back(v)}
    });stack.pop_back()
}
public fun rule(key:vector<u8>,kind:u8,trigger:Selector,any:bool,targets:vector<Selector>):Rule{
    key(&key);assert!(kind<=1 && !targets.is_empty() && targets.length()<=32,EBounds);
    let mut seen=vector[];targets.do_ref!(|t|{assert!(!seen.contains(t),EDuplicate);seen.push_back(*t)});Rule{key,kind,trigger,any,targets}
}
public fun anchor(key:vector<u8>,when:vector<Token>,x:Signed,y:Signed):Anchor{key(&key);validate_program(&when);Anchor{key,when,x,y}}
fun assert_selector_parts(s:&Selector,parts:&vector<vector<u8>>){assert!(parts.contains(&s.part),EReference)}
fun assert_program_parts(ts:&vector<Token>,parts:&vector<vector<u8>>){ts.do_ref!(|t|t.selector.do_ref!(|s|assert_selector_parts(s,parts)))}
public fun scene(width:u64,height:u64,origin_x:Signed,origin_y:Signed,sampling:u8,renderer:vector<u8>,body:vector<u8>,pose:vector<u8>,parts:vector<vector<u8>>,tracks:vector<Track>,channels:vector<Channel>,anchors:vector<Anchor>,rules:vector<Rule>):Scene{
    assert!(width>0 && height>0 && width<=8192 && height<=8192 && width*height<=MAX_PIXELS && sampling<=1,EBounds);
    digest(&renderer);key(&body);key(&pose);
    assert!(!parts.is_empty() && parts.length()<=64 && !tracks.is_empty() && tracks.length()<=256 && channels.length()<=256 && !anchors.is_empty() && anchors.length()<=256 && rules.length()<=256,EBounds);
    let mut seen=vector[];parts.do_ref!(|p|{key(p);assert!(!seen.contains(p),EDuplicate);seen.push_back(*p)});
    seen=vector[];let mut i=0;tracks.do_ref!(|t|{assert!(!seen.contains(&t.key),EDuplicate);seen.push_back(t.key);if(i>0)assert!(tracks[i-1].order<=t.order,EInvalid);i=i+1});
    seen=vector[];let mut count=0;channels.do_ref!(|c|{assert!(!seen.contains(&c.key),EDuplicate);seen.push_back(c.key);count=count+c.swatches.length()});assert!(count<=5000,EBounds);
    let mut variants=vector[];anchors.do_ref!(|a|{assert_program_parts(&a.when,&parts);let h=hash::sha2_256(bcs::to_bytes(&AnchorVariant{key:a.key,when:a.when}));assert!(!variants.contains(&h),EDuplicate);variants.push_back(h)});
    seen=vector[];rules.do_ref!(|r|{assert!(!seen.contains(&r.key),EDuplicate);seen.push_back(r.key);assert_selector_parts(&r.trigger,&parts);r.targets.do_ref!(|s|assert_selector_parts(s,&parts))});
    let s=Scene{domain:b"soulidity/scene/v1",schema:1,width,height,origin_x,origin_y,axes:0,sampling,clip_viewport:true,color_space:0,premultiplied:true,renderer,body,pose,parts,tracks,channels,anchors,rules};
    assert!(bcs::to_bytes(&s).length()<=131072,EBounds);s
}
public fun scene_hash(s:&Scene):vector<u8>{hash::sha2_256(bcs::to_bytes(s))}
/// A body/pose view can change canvas, placement and track/anchor resolution.
/// It cannot silently change the published selection or Smart Color/Rules
/// contract. Asset bytes, fixed Styles and user transforms remain separate.
public fun assert_variant_contract(original:&Scene,target:&Scene){
    assert!(original.domain==target.domain && original.schema==target.schema
        && original.axes==target.axes && original.sampling==target.sampling
        && original.clip_viewport==target.clip_viewport && original.color_space==target.color_space
        && original.premultiplied==target.premultiplied && original.renderer==target.renderer
        && original.parts==target.parts && original.channels==target.channels
        && original.rules==target.rules,EReference)
}
public fun renderer(s:&Scene):vector<u8>{s.renderer}
public fun parts(s:&Scene):vector<vector<u8>>{s.parts}
public fun dimensions(s:&Scene):(u64,u64){(s.width,s.height)}
public fun tracks(s:&Scene):&vector<Track>{&s.tracks}
public fun channels(s:&Scene):&vector<Channel>{&s.channels}
public fun anchors(s:&Scene):&vector<Anchor>{&s.anchors}
public fun rules(s:&Scene):&vector<Rule>{&s.rules}
public fun selector_part(s:&Selector):vector<u8>{s.part}
public fun selector_item(s:&Selector):Option<vector<u8>>{s.item}
public fun selector_style(s:&Selector):Option<vector<u8>>{s.style}
public fun rule_trigger(r:&Rule):&Selector{&r.trigger}
/// A Pack may add rows, but cannot alter, remove or reorder inherited rows.
/// Tracks can be inserted between inherited orders; their relative order is fixed.
public fun assert_additive(base:&Scene,extended:&Scene){
    assert!(base.domain==extended.domain && base.schema==extended.schema && base.width==extended.width && base.height==extended.height && base.origin_x==extended.origin_x && base.origin_y==extended.origin_y && base.axes==extended.axes && base.sampling==extended.sampling && base.clip_viewport==extended.clip_viewport && base.color_space==extended.color_space && base.premultiplied==extended.premultiplied && base.renderer==extended.renderer && base.body==extended.body && base.pose==extended.pose,EReference);
    assert!(base.parts.length()<=extended.parts.length() && base.channels.length()<=extended.channels.length() && base.anchors.length()<=extended.anchors.length() && base.rules.length()<=extended.rules.length(),EReference);
    let mut i=0;while(i < base.parts.length()){assert!(base.parts[i]==extended.parts[i],EReference);i=i+1};
    i=0;while(i < base.channels.length()){assert!(base.channels[i]==extended.channels[i],EReference);i=i+1};
    i=0;while(i < base.anchors.length()){assert!(base.anchors[i]==extended.anchors[i],EReference);i=i+1};
    i=0;while(i < base.rules.length()){assert!(base.rules[i]==extended.rules[i],EReference);i=i+1};
    let mut inherited=vector[];extended.tracks.do_ref!(|t|{if(base.tracks.any!(|b|b.key==t.key))inherited.push_back(*t)});assert!(inherited==base.tracks,EReference);
    // An added variant with an inherited anchor key would change resolution.
    i=base.anchors.length();while(i < extended.anchors.length()){assert!(!base.anchors.any!(|a|a.key==extended.anchors[i].key),EReference);i=i+1}
}
/// Added rules may constrain a Pack-owned Part or a published Pack item/style.
/// They cannot impose a new generic trigger on an inherited Maker Part.
public fun assert_pack_rule_owners(base:&Scene,extended:&Scene,owned_parts:&vector<vector<u8>>,owned:&vector<Selector>){
    let mut i=base.rules.length();while(i < extended.rules.length()){
        let trigger=&extended.rules[i].trigger;
        assert!(trigger.product.is_none() && (if(trigger.item.is_none())owned_parts.contains(&trigger.part) && !base.parts.contains(&trigger.part) else owned.any!(|o|o.part==trigger.part && o.item==trigger.item && (trigger.style.is_none() || o.style==trigger.style))),ERule);i=i+1
    }
}
/// All local rule/anchor/visibility paths must resolve to actual published rows.
/// Exact external selectors are refused until certified dependency admission.
public fun assert_local_references(s:&Scene,rows:&vector<Selector>,representations:&vector<Representation>){
    assert_scene_references(s,rows);representations.do_ref!(|r|assert_representation_references(s,rows,r))
}
/// Borrow-only metadata validators. No Product/Soul mutation or authority.
public fun assert_scene_references(s:&Scene,rows:&vector<Selector>){
    s.anchors.do_ref!(|a|assert_program_rows(&a.when,&s.parts,rows));
    s.rules.do_ref!(|r|{assert_selector_row(&r.trigger,&s.parts,rows);r.targets.do_ref!(|t|assert_selector_row(t,&s.parts,rows))})
}
public fun assert_representation_references(s:&Scene,rows:&vector<Selector>,r:&Representation){
    assert_program_rows(&r.visible,&s.parts,rows);r.fragments.do_ref!(|f|assert_program_rows(&f.visible,&s.parts,rows))
}
fun assert_selector_row(s:&Selector,parts:&vector<vector<u8>>,rows:&vector<Selector>){
    assert!(s.product.is_none(),EReference);
    assert!(parts.contains(&s.part),EReference);
    if(s.item.is_some())assert!(rows.any!(|r|r.part==s.part && r.item==s.item && (s.style.is_none() || r.style==s.style)),EReference)
}
fun assert_program_rows(ts:&vector<Token>,parts:&vector<vector<u8>>,rows:&vector<Selector>){ts.do_ref!(|t|t.selector.do_ref!(|s|assert_selector_row(s,parts,rows)))}
/// None retains each fixed Style's own default swatch; linked channels override
/// all participating fragments only after the player explicitly chooses one.
public fun default_colors(s:&Scene):vector<ColorChoice>{s.channels.map_ref!(|c|ColorChoice{channel:c.key,swatch:option::none()})}
public fun assert_colors(s:&Scene,choices:&vector<ColorChoice>){
    assert!(choices.length()==s.channels.length(),EColor);let mut i=0;
    choices.do_ref!(|c|{let channel=&s.channels[i];assert!(channel.key==c.channel,EColor);if(c.swatch.is_some())assert!(channel.editable && channel.swatches.any!(|w|option::some(w.key)==c.swatch),EColor);i=i+1})
}
public fun assert_rules(s:&Scene,facts:&vector<Fact>){
    s.rules.do_ref!(|r|{if(selected(&r.trigger,facts)){
        if(r.kind==0)assert!(if(r.any)r.targets.any!(|t|selected(t,facts)) else r.targets.all!(|t|selected(t,facts)),ERule)
        else assert!(!r.targets.any!(|t|selected(t,facts)),ERule)
    }})
}
/// Inherited rules run once in the root scope. Added triggers only see their
/// own Pack components/Parts; another Pack's same-name Style cannot trigger them.
public fun assert_pack_rules(base:&Scene,pack:&Scene,facts:&vector<Fact>,owned:&vector<Fact>){
    let mut i=base.rules.length();while(i < pack.rules.length()){let r=&pack.rules[i];if(selected(&r.trigger,owned)){
        if(r.kind==0)assert!(if(r.any)r.targets.any!(|t|selected(t,facts)) else r.targets.all!(|t|selected(t,facts)),ERule)
        else assert!(!r.targets.any!(|t|selected(t,facts)),ERule)
    };i=i+1}
}
public fun resolve_anchor(s:&Scene,key:vector<u8>,facts:&vector<Fact>):Anchor{
    let mut found=option::none();s.anchors.do_ref!(|a|{if(a.key==key && evaluate(&a.when,facts)){assert!(found.is_none(),ERule);found=option::some(*a)}});assert!(found.is_some(),EReference);found.destroy_some()
}
public fun fragment(key:vector<u8>,asset:vector<u8>,media:vector<u8>,byte_length:u64,image_width:u64,image_height:u64,crop_x:u64,crop_y:u64,crop_width:u64,crop_height:u64,local_x:u64,local_y:u64,track:vector<u8>,display_order:u64,anchor:vector<u8>,transform:Transform,opacity_ppm:u64,blend:u8,channel:Option<vector<u8>>,swatch:Option<vector<u8>>,mask:Option<u64>,visible:vector<Token>):Fragment{
    key(&key);digest(&asset);key(&track);key(&anchor);validate_program(&visible);
    assert!((media==b"image/png" || media==b"image/webp" || media==b"image/jpeg") && byte_length>0 && byte_length<=8388608,EBounds);
    assert!(image_width>0 && image_height>0 && image_width<=8192 && image_height<=8192 && image_width*image_height<=MAX_PIXELS,EBounds);
    assert!(crop_width>0 && crop_height>0 && crop_x<=image_width && crop_y<=image_height && crop_width<=image_width-crop_x && crop_height<=image_height-crop_y && local_x<=image_width*1000 && local_y<=image_height*1000,EBounds);
    assert!(opacity_ppm<=1000000 && blend < 17 && channel.is_some()==swatch.is_some(),EInvalid);
    channel.do_ref!(|c|key(c));swatch.do_ref!(|w|key(w));
    Fragment{key,asset,media,byte_length,image_width,image_height,crop_x,crop_y,crop_width,crop_height,local_x,local_y,track,display_order,anchor,transform,opacity_ppm,blend,channel,swatch,mask,visible}
}
public fun representation(scene:&Scene,canvas_width:u64,canvas_height:u64,fragments:vector<Fragment>,visible:vector<Token>):Representation{
    assert!(canvas_width>0 && canvas_height>0 && canvas_width<=8192 && canvas_height<=8192 && canvas_width*canvas_height<=MAX_PIXELS && !fragments.is_empty() && fragments.length()<=MAX_FRAGMENTS,EBounds);
    validate_program(&visible);assert_program_parts(&visible,&scene.parts);assert_unique_keys(fragments.map_ref!(|f|f.key));let mut i=0;let mut depths=vector[];
    fragments.do_ref!(|f|{
        assert_fragment_target(scene,f.track,f.anchor,f.channel,f.swatch);assert_program_parts(&f.visible,&scene.parts);
        let depth=if(f.mask.is_some()){let index=*f.mask.borrow();assert!(index < i,EReference);depths[index]+1} else 0;
        assert!(depth<=8,EBounds);depths.push_back(depth);i=i+1
    });
    let r=Representation{domain:b"soulidity/representation/v1",schema:1,scene_hash:scene_hash(scene),renderer:scene.renderer,canvas_width,canvas_height,fragments,visible};assert!(bcs::to_bytes(&r).length()<=131072,EBounds);r
}
fun assert_fragment_target(scene:&Scene,track:vector<u8>,anchor:vector<u8>,channel:Option<vector<u8>>,swatch:Option<vector<u8>>){
    assert!(scene.tracks.any!(|t|t.key==track) && scene.anchors.any!(|a|a.key==anchor),EReference);
    if(channel.is_some())assert!(scene.channels.any!(|c|c.key==*channel.borrow() && c.swatches.any!(|w|w.key==*swatch.borrow())),EColor)
}
public fun representation_hash(r:&Representation):vector<u8>{hash::sha2_256(bcs::to_bytes(r))}
/// Validated value construction only. This never edits a Product, Definition,
/// Soul, Item, authorization or any published representation. Returns a new value;
/// the owning contract still controls whether that value can be installed.
public fun extend_representation(r:&Representation,scene:&Scene,extra:vector<Fragment>):Representation{
    assert_native(r,scene);assert!(r.fragments.length()+extra.length()<=MAX_FRAGMENTS,EBounds);
    // Existing rows are already constructor-validated and private. Do not
    // recheck every old pair for each small append; validate each new row once.
    let mut fragments=r.fragments;let mut keys=fragments.map_ref!(|f|f.key);keys.append(extra.map_ref!(|f|f.key));assert_unique_keys(keys);let mut depths=vector[];
    fragments.do_ref!(|f|{let depth=if(f.mask.is_some())depths[*f.mask.borrow()]+1 else 0u64;depths.push_back(depth)});
    extra.do!(|f|{assert_fragment_target(scene,f.track,f.anchor,f.channel,f.swatch);assert_program_parts(&f.visible,&scene.parts);let i=fragments.length();let depth=if(f.mask.is_some()){let index=*f.mask.borrow();assert!(index < i,EReference);depths[index]+1} else 0;assert!(depth<=8,EBounds);depths.push_back(depth);fragments.push_back(f)});
    let n=Representation{domain:r.domain,schema:r.schema,scene_hash:r.scene_hash,renderer:r.renderer,canvas_width:r.canvas_width,canvas_height:r.canvas_height,fragments,visible:r.visible};assert!(bcs::to_bytes(&n).length()<=131072,EBounds);n
}
public fun representation_scene(r:&Representation):vector<u8>{r.scene_hash}
public fun representation_renderer(r:&Representation):vector<u8>{r.renderer}
public fun fragments(r:&Representation):&vector<Fragment>{&r.fragments}
public fun assert_native(r:&Representation,s:&Scene){assert!(r.scene_hash==scene_hash(s) && r.renderer==s.renderer,EReference)}
public fun fragment_map(index:u64,track:vector<u8>,anchor:vector<u8>,transform:Transform,channel:Option<vector<u8>>,swatch:Option<vector<u8>>):FragmentMap{
    key(&track);key(&anchor);assert!(channel.is_some()==swatch.is_some(),EInvalid);channel.do_ref!(|c|key(c));swatch.do_ref!(|w|key(w));FragmentMap{index,track,anchor,transform,channel,swatch}
}
public fun mapping(r:&Representation,target:&Scene,maps:vector<FragmentMap>):Mapping{
    assert!(maps.length()==r.fragments.length() && r.renderer==target.renderer,EReference);let mut i=0;
    maps.do_ref!(|m|{assert!(m.index==i,EReference);assert_fragment_target(target,m.track,m.anchor,m.channel,m.swatch);i=i+1});
    Mapping{representation:representation_hash(r),scene:scene_hash(target),maps}
}
public fun assert_mapping(r:&Representation,s:&Scene,m:&Mapping){assert!(m.representation==representation_hash(r) && m.scene==scene_hash(s) && m.maps.length()==r.fragments.length(),EReference)}
public fun mapping_scene(m:&Mapping):vector<u8>{m.scene}
public fun mapping_hash(m:&Mapping):vector<u8>{hash::sha2_256(bcs::to_bytes(m))}
public fun render_layers(s:&Scene,r:&Representation,mapping:&Option<Mapping>,source:vector<u8>,fact:Fact,facts:&vector<Fact>,colors:&vector<ColorChoice>,user:Transform,tint:vector<u8>):vector<Layer>{
    digest(&source);assert_colors(s,colors);assert!(evaluate(&r.visible,facts),ERule);
    if(mapping.is_some())assert_mapping(r,s,mapping.borrow()) else assert_native(r,s);
    let mut layers=vector[];let mut i=0;
    r.fragments.do_ref!(|f|{
        if(evaluate(&f.visible,facts)){
            let map=if(mapping.is_some())option::some(mapping.borrow().maps[i]) else option::none();
            let track=if(map.is_some())map.borrow().track else f.track;let anchor=if(map.is_some())map.borrow().anchor else f.anchor;
            let channel=if(map.is_some())map.borrow().channel else f.channel;
            let fallback=if(map.is_some())map.borrow().swatch else f.swatch;
            let mut color=option::none();if(channel.is_some()){
                let channel=*channel.borrow();let mut chosen=fallback;
                colors.do_ref!(|c|{if(c.channel==channel && c.swatch.is_some())chosen=c.swatch});
                s.channels.do_ref!(|c|{if(c.key==channel)c.swatches.do_ref!(|w|{if(w.key==*chosen.borrow())color=option::some(*w)})});assert!(color.is_some(),EColor)
            };
            let mut target=option::none();s.tracks.do_ref!(|t|{if(t.key==track)target=option::some(*t)});
            if(f.mask.is_some())assert!(evaluate(&r.fragments[*f.mask.borrow()].visible,facts),ERule);
            assert!(tint.is_empty() || (tint.length()==4 && channel.is_none()),EColor);
            layers.push_back(Layer{source,part:fact.part,item:fact.item,style:fact.style,index:i,track:target.destroy_some(),fragment:*f,anchor:resolve_anchor(s,anchor,facts),adapter:map.map_ref!(|m|m.transform),user,tint,color})
        };i=i+1
    });layers
}
/// Explicit lexical bytes match the protocol text ordering for UTF-8 keys.
fun less_bytes(a:&vector<u8>,b:&vector<u8>):bool{let mut i=0;while(i < a.length() && i < b.length()){if(a[i]!=b[i])return a[i] < b[i];i=i+1};a.length()<b.length()}
/// Sort only a projection of exact keys. Fragment order, display order and mask
/// indices stay untouched. Heap sort bounds comparisons/swaps to O(n log n);
/// the stdlib in-place merge uses element shifting and can be quadratic.
fun sift_keys(keys:&mut vector<vector<u8>>,start:u64,end:u64){
    let mut parent=start;
    while(parent < end/2){
        let mut child=parent*2+1;
        if(child+1 < end && less_bytes(&keys[child],&keys[child+1]))child=child+1;
        if(!less_bytes(&keys[parent],&keys[child]))return;
        keys.swap(parent,child);parent=child
    }
}
fun assert_unique_bucket(mut keys:vector<vector<u8>>){
    let n=keys.length();if(n < 2)return;
    let mut start=n/2;while(start>0){start=start-1;sift_keys(&mut keys,start,n)};
    let mut end=n;while(end>1){end=end-1;keys.swap(0,end);sift_keys(&mut keys,0,end)};
    let mut i=1;while(i < n){assert!(keys[i-1]!=keys[i],EDuplicate);i=i+1}
}
// Equal exact keys share their first byte. All remaining bytes are compared
// inside each bucket; no Fragment, display order or mask index is reordered.
fun assert_unique_keys(keys:vector<vector<u8>>){
    if(keys.length()<=32){assert_unique_bucket(keys);return};
    let mut buckets:vector<vector<vector<u8>>> = vector::tabulate!(256,|_|vector[]);
    keys.do!(|key|buckets[key[0] as u64].push_back(key));
    buckets.do!(|bucket|assert_unique_bucket(bucket))
}
fun before(a:&Layer,b:&Layer):bool{
    if(a.track.order!=b.track.order)return a.track.order < b.track.order;
    if(a.fragment.display_order!=b.fragment.display_order)return a.fragment.display_order < b.fragment.display_order;
    if(a.part!=b.part)return less_bytes(&a.part,&b.part);
    if(a.item!=b.item)return less_bytes(&a.item,&b.item);
    if(a.style!=b.style)return less_bytes(&a.style,&b.style);
    if(a.source!=b.source)return less_bytes(&a.source,&b.source);a.index < b.index
}
public fun ordered(mut layers:vector<Layer>):vector<Layer>{
    assert!(layers.length()<=MAX_FRAGMENTS,EBounds);let mut pixels=0;let mut bytes=0;
    layers.do_ref!(|l|{pixels=pixels+l.fragment.image_width*l.fragment.image_height;bytes=bytes+l.fragment.byte_length});assert!(pixels<=134217728 && bytes<=67108864,EBounds);let mut i=1;
    while(i < layers.length()){let mut j=i;while(j>0 && before(&layers[j],&layers[j-1])){layers.swap(j,j-1);j=j-1};i=i+1};layers
}
public fun layer_fragment(l:&Layer):&Fragment{&l.fragment}
public fun layer_track(l:&Layer):&Track{&l.track}
public fun layer_anchor(l:&Layer):&Anchor{&l.anchor}
public fun layer_color(l:&Layer):Option<Swatch>{l.color}
public fun layer_user(l:&Layer):Transform{l.user}
public fun transform_parts(t:&Transform):(Signed,Signed,u64,Signed){(t.x,t.y,t.scale_ppm,t.rotation)}
public fun track_key(t:&Track):vector<u8>{t.key}
public fun fragment_key(f:&Fragment):vector<u8>{f.key}
public fun fragment_asset(f:&Fragment):vector<u8>{f.asset}
public fun fragment_bytes(f:&Fragment):u64{f.byte_length}
public fun fragment_blend(f:&Fragment):u8{f.blend}
public fun anchor_position(a:&Anchor):(Signed,Signed){(a.x,a.y)}
public fun signed_parts(s:&Signed):(bool,u64){(s.negative,s.magnitude)}
public fun swatch_stops(s:&Swatch):&vector<Stop>{&s.stops}
public fun swatch_key(s:&Swatch):vector<u8>{s.key}
public fun channel_key(c:&Channel):vector<u8>{c.key}
public fun choice_channel(c:&ColorChoice):vector<u8>{c.channel}
public fun choice_swatch(c:&ColorChoice):Option<vector<u8>>{c.swatch}
public fun stop_value(s:&Stop):(u64,u32){(s.offset_ppm,s.rgba)}
