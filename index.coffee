svg = d3.select('body').append('svg')
    .attr('width', '100%')
    .attr('height', '100%')

width = svg[0][0].getBoundingClientRect().width
height = svg[0][0].getBoundingClientRect().height

console.debug 'Loading overlay...'

s = Snap('svg')
Snap.load 'overlay.svg', (f) ->
    console.debug "Loaded."

    defs = svg.append('defs')

    # projection = d3.geo.mercator()
        # .scale(2800)
        # .translate([50, 2620])
        # .precision(0.1)

    # projection = d3.geo.albers()
        # .center([14, 34])
        # .rotate([-14, 0])
        # .parallels([38, 61])
        # .scale(2100)

    projection = d3.geo.azimuthalEqualArea()
        .clipAngle(180 - 1e-3)
        .scale(3000)
        .rotate([-12.22, -42, 0])
        .translate([width / 2, height / 2])
        .precision(.1)

    # graticule = d3.geo.graticule()
        # .step([1,1])

    path_generator = d3.geo.path()
        .projection(projection)

    map = svg.append('g')
        .attr('id', 'map')

    ### draw the graticule ###
    # map.append('path')
        # .datum(graticule)
        # .attr('class', 'graticule')
        # .attr('d', path_generator)

    ### define a zoom behavior ###
    zoom = d3.behavior.zoom()
        .scaleExtent([1,100]) # min-max zoom
        .on 'zoom', () ->
          # whenever the user zooms,
          # modify translation and scale of the zoom group accordingly
          map.attr('transform', "translate(#{zoom.translate()})scale(#{zoom.scale()})")

    ### bind the zoom behavior to the main SVG ###
    svg.call(zoom)

    console.debug 'Retrieving data...'
    queue()
      .defer(d3.json, 'data/istat/italy2011_g.topo.json')
      .defer(d3.csv, 'data/langs.csv')
      .defer(d3.csv, 'data/comuniXlangs.csv')
      .await (error, italy, langs, comuniXlangs) ->
        console.debug 'Extracting ISO codes...'
        langs_index = {}
        for l in langs
            langs_index[l['ISO 639-3']] = l

        lang2color = d3.scale.ordinal()
            .domain(['frp',    'pms',    'oci',    'wae',    'lmo',    'lij',    'egl',    'vec',    'fur',    'slv',    'lld',    'deu',    'bar',    'cim',    'mhn',    'rgn',    'nap',    'scn',    'aae',    'svm',    'ell',    'sro',    'src',    'sdn',    'sdc',    'cos',    'itk',    'cat'    ])
            .range([ '#FAE9BD','#A06C90','#00B1AE','#E2007F','#FFB752','#8C9208','#B94A51','#E1DAC5','#E5571D','#343055','#567C87','#D3B3D8','#5FBD47','#857548','#6F067B','#DFCD11','#80BCA3','#CFC8A2','#7D4A04','#F59EE5','#EF1C25','#E9BD07','#888A85','#C5EAF6','#729FCF','#000000','#000000','#FFF210'])

        console.debug 'Indexing comuniXlangs and creating hatch patterns...'
        comuni_index = {}
        hatches = {nodata:{size:8,c:['#EEE','#E6E6E6'],id:'nodata'}}
        hatch_size2 = 2
        for cl in comuniXlangs
            if cl.lingue is ''
                langs = []
            else
                langs = cl.lingue.split(',').filter((d)->d isnt 'ita')

            langs.sort()
            comuni_index[cl.cod_com] = {name: cl.nome_com, langs: langs}

            key = langs.join('_')
            if langs.length is 2 and key not in hatches
                hatches[key] = {size: hatch_size2, c:[lang2color(langs[0]), lang2color(langs[1])], id:key}
            else if langs.length is 3 and key not in hatches
                hatches[key] = {size: 3*hatch_size2/2, c:[lang2color(langs[0]), lang2color(langs[1]), lang2color(langs[2])], id:key}
            else if langs.length > 3
                throw 'Italang does not support more than 3 language colors per region!'

        # need an array
        hatches = (h for k, h of hatches)

        new_patterns = defs.selectAll('.hatch')
            .data(hatches)
          .enter().append('pattern')
            .attr('class', 'hatch')
            .attr('id', (d)->d.id)
            .attr('patternUnits', 'userSpaceOnUse')
            .attr('width', (d)->d.size)
            .attr('height', (d)->d.size)

        new_patterns.append('rect')
            .attr('x',0)
            .attr('y',0)
            .attr('width', (d)->d.size)
            .attr('height', (d)->d.size)
            .attr('fill', (d)->d.c[0])

        new_patterns.append('path')
            .attr('d', (d) -> """
                M0 0 L#{d.size/d.c.length} 0 L0 #{d.size/d.c.length} z
                M#{d.size} 0 L#{d.size} #{d.size/d.c.length} L#{d.size/d.c.length} #{d.size} L0 #{d.size} z
             """)
            .attr('fill', (d)->d.c[1])

        new_patterns.filter((d)->d.c.length is 3).append('path')
            .attr('d', (d) -> """
                M#{d.size/3} 0 L#{2*d.size/3} 0 L0 #{2*d.size/3} L0 #{d.size/3} z
                M#{d.size} #{d.size/3} L#{d.size} #{2*d.size/3} L#{2*d.size/3} #{d.size} L#{d.size/3} #{d.size} z
             """)
            .attr('fill', (d)->d.c[2])


        console.debug 'Extracting TopoJSON features...'
        regioni = topojson.feature(italy, italy.objects.reg2011_g)
        province = topojson.feature(italy, italy.objects.prov2011_g)
        comuni = topojson.feature(italy, italy.objects.com2011_g)

        console.debug 'Drawing...'

        comuni = map.selectAll('.comune')
            .data(comuni.features)
          .enter().append('path')
            .attr('class', 'comune')
            .attr('d', path_generator)
            .attr('fill', (d) ->
                if d.properties.PRO_COM not of comuni_index
                    console.warn "#{d.properties.PRO_COM} not found in index."
                    return 'black'

                info = comuni_index[d.properties.PRO_COM]
                if info.langs.length is 1
                    return lang2color(comuni_index[d.properties.PRO_COM].langs[0])
                else if info.langs.length is 0
                    return 'white'
                else
                    return "url(##{info.langs.join('_')})"
            )

        comuni.append('title')
            .text((d) ->
                if d.properties.PRO_COM not of comuni_index
                    console.warn "#{d.properties.PRO_COM} not found in index."
                    return '???'

                info = comuni_index[d.properties.PRO_COM]
                return "#{info.name}\n#{(langs_index[lang].Lingua_IT for lang in info.langs).join(', ')}"
            )

        console.debug 'Adding borders...'
        map.append('path')
            .datum(topojson.mesh(italy, italy.objects.com2011_g, (a, b) -> a.properties.COD_REG isnt b.properties.COD_REG))
            .attr('d', path_generator)
            .attr('class', 'regioni')

        map.append('path')
            .datum(topojson.mesh(italy, italy.objects.prov2011_g, (a, b) -> a is b))
            .attr('d', path_generator)
            .attr('class', 'italia')

        console.debug 'Adding overlay...'

        overlay = f.select('#overlay')
        s.select('#map').append(overlay)

        overlay.attr
            transform: "translate(#{width/2-350},#{height/2-500})"
