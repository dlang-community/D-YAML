window.onload = function(e)
{
    var elems = document.querySelectorAll( "div.toc ul ul" );
    for( i in elems )
    {
        if( elems[i].style.display != "block" )
            elems[i].style.display = "none";
    }
}

function show_hide(id) 
{ 
    var elem = document.getElementById( id ); 
    if( elem.style.display == "block" ) 
        elem.style.display = "none"; 
    else elem.style.display = "block"; 
}
