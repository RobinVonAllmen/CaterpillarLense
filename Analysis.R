library(ggplot2)
raw <- read.csv("test.csv", sep=";")

#ID - 31 not meassured correctly. 
raw <- raw[-31,]

mod <- lm(log(weight..mg.) ~ log(area.mm.2), data =raw)
summary(mod)

plot(mod)

reg.plot <- ggplot(data=raw, mapping = aes(y=log(weight..mg.), x=log(area.mm.2)))+
  geom_abline(slope = mod$coefficients[2], intercept = mod$coefficients[1], col="blue", lwd =1)+
  geom_point()+
  scale_x_continuous(name=expression(ln(Area~"["~mm^2~"]")))+
  scale_y_continuous(name=expression(ln(Weight~"["~mg~"]")))+
  theme_bw()+
  theme(
    axis.title = element_text(size = 12),
    axis.text = element_text(size = 10)
  )

ggsave("figure_2.tiff",
       plot = reg.plot,
       width = 16,
       height = 9,
       units = "cm",
       dpi = 600)

library(lmtest)
resettest(mod)  # Ramsey RESET test
bptest(mod) 
shapiro.test(residuals(mod))


# Check for outliers
library(performance)
check_outliers(mod)
check_normality(mod)

cor.test(raw$weight..mg., raw$area.mm.2, method = "pearson")
