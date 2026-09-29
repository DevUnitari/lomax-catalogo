INSERT INTO categorias (categoria_id, nombre) VALUES
 (1,'Teclados'),(2,'Monitores'),(3,'Televisores')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO productos (producto_id, codigo, nombre, descripcion, precio, categoria_id) VALUES
 (1,'TEC-001','Teclado Mecanico Redragon Kumara','Teclado mecanico compacto retroiluminado',45.90,1),
 (2,'TEC-002','Teclado Logitech K380','Teclado inalambrico multidispositivo',39.99,1),
 (3,'TEC-003','Teclado Corsair K70','Teclado mecanico gamer con switches rapidos',129.00,1),
 (4,'TEC-004','Teclado Razer BlackWidow','Teclado mecanico con iluminacion RGB',119.50,1),
 (5,'TEC-005','Teclado HP 150','Teclado basico con cable USB',15.00,1),
 (6,'TEC-006','Teclado Keychron K2','Teclado mecanico inalambrico 75%',89.00,1),
 (7,'TEC-007','Teclado Microsoft Ergonomic','Teclado ergonomico de perfil bajo',59.00,1),
 (8,'MON-001','Monitor Samsung 24 Full HD','Monitor IPS de 24 pulgadas',139.00,2),
 (9,'MON-002','Monitor LG UltraGear 27','Monitor gamer 27 pulgadas 144Hz',229.00,2),
 (10,'MON-003','Monitor Dell P2422H','Monitor profesional 24 pulgadas',175.00,2),
 (11,'MON-004','Monitor AOC 32 QHD','Monitor curvo de 32 pulgadas',259.00,2),
 (12,'MON-005','Monitor ASUS ProArt 27','Monitor 4K para diseno',449.00,2),
 (13,'MON-006','Monitor Acer 22 HD','Monitor economico de 22 pulgadas',99.00,2),
 (14,'MON-007','Monitor BenQ 27 2K','Monitor 27 pulgadas resolucion 2K',199.00,2),
 (15,'TV-001','Televisor Samsung 43 4K','Smart TV 43 pulgadas 4K',329.00,3),
 (16,'TV-002','Televisor LG 50 4K','Smart TV 50 pulgadas 4K',389.00,3),
 (17,'TV-003','Televisor Sony 55 4K','Smart TV 55 pulgadas Google TV',549.00,3),
 (18,'TV-004','Televisor TCL 32 HD','Smart TV 32 pulgadas HD',159.00,3),
 (19,'TV-005','Televisor Hisense 65 4K','Smart TV 65 pulgadas 4K',599.00,3),
 (20,'TV-006','Televisor Philips 43 FHD','TV 43 pulgadas Full HD',249.00,3)
ON CONFLICT (codigo) DO NOTHING;

SELECT setval('categorias_categoria_id_seq', (SELECT MAX(categoria_id) FROM categorias));
SELECT setval('productos_producto_id_seq',   (SELECT MAX(producto_id)   FROM productos));
